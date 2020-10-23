### Deep Dive into the problem

### Table of Contents
1. [Installation](README.md#installation)
    - [Proxmox - premade packages](README.md#proxmox---premade-packages)
    - [Proxmox - building from sources](README.md#proxmox---building-from-sources)
    - [Other distros](README.md#other-distros)
2. [Configuration](README.md#configuration)
3. **Deep Dive** <= you're here
    - [Technical details](deep-dive.md#technical-details)
        - [How virtual machines use memory?](deep-dive.md#how-virtual-machines-use-memory)
        - [Why do we need VT-d / AMD-Vi?](deep-dive.md#why-do-we-need-vt-d--amd-vi)
        - [How PCI/PCIe actually work?](deep-dive.md#how-pcipcie-actually-work)
        - [RMRR - the monster in a closet](deep-dive.md#rmrr---the-monster-in-a-closet)
        - [What vendors did wrong?](deep-dive.md#what-vendors-did-wrong)
    - [Other solutions & hacks](deep-dive.md#other-solutions--hacks)
        - [Contact your platform vendor](deep-dive.md#contact-your-platform-vendor)
        - [Use OS which ignores RMRRs](deep-dive.md#use-os-which-ignores-rmrrs)
        - [Attempt HPE's pseudofix (if you use HP)](deep-dive.md#attempt-hpes-pseudofix-if-you-use-hp)
        - [The comment-the-error-out hack (v3.17 - 5.3)](deep-dive.md#the-comment-the-error-out-hack-v317---53)
        - [Long-term solution - utilizing relaxable reservation regions (>=3.17)](deep-dive.md#long-term-solution---utilizing-relaxable-reservation-regions-317)
          - [Why commenting-out the error is a bad idea](deep-dive.md#why-commenting-out-the-error-is-a-bad-idea)
          - [The kernel moves on quickly](deep-dive.md#the-kernel-moves-on-quickly)
          - [What this patch actually does](deep-dive.md#what-this-patch-actually-does)
          - [Why kernel patch and not a loadable module?](deep-dive.md#why-kernel-patch-and-not-a-loadable-module)
        - [The future](deep-dive.md#the-future)    
4. [Disclaimers](README.md#disclaimers)
5. [Acknowledgments & References](README.md#acknowledgments--references)
6. [License](README.md#license)

---

### Technical details

#### How virtual machines use memory?
To understand PCI passthrough we first need to understand how VMs work. Each VM launched in the system gets a new 
virtual address space and has no direct access to the host memory. Yet, the guest OS runs like it was running with a 
real RAM, using any memory addresses it wants. In other words the guest OS has no idea (in terms of memory) that it is 
being virtualized. Logically there has to be some map to translate guest OS requests to the real memory addresses, since
multiple guest OSes has to share the same physical host memory. The hypervisor (host OS) is responsible for maintaining 
a map between GPA (Guest Address Space) and HPA (Host Physical Address). To better understand this look at the (VERY 
simplified) graphics:

```
+--------------------------------HOST----------------------------------------+
|                                                                            |
|  +--------------------------HOST MEMORY-------------------------------+    |
|  | +-------+                 +----------GUEST MEMORY-----------+      |    |
|  | |  vim  |                 |---------------------------------|      |    |
|  | |  mem  |                 |---------------------------------|      |    |
|  | +-------+                 +---------------------------------+      |    |
|  | 0xA000  0xA100                                                     |    |
|  +--------------------------------------------------------------------+    |
|  0x0000                      0xF000                          0xF0FF  0x....|
|                                                                            |
|    +--------+  +----------------GUEST VM------------------+                |
|    |        |  | +------------GUEST MEMORY--------------+ |                |
|    |  vim   |  | |             |        |               | |                |
|    |        |  | | guest kernel| wget   |               | |                |
|    +--------+  | |             | mem    |               | |                |
|                | +-------------+--------+---------------+ |                |
|                | 0x00          0x1E     0x20         0xFF |                |
|                |                 +------+                 |                |
|                |                 | wget |                 |                |
|                |                 +------+                 |                |
|                +------------------------------------------+                |
+----------------------------------------------------------------------------+

(addresses don't represent real x86 space[!] and are not drawn to scale)
```

When a VM is run the hypervisor gives it a predetermined amount of memory and tells the gust OS that it has a contagious
space of 255 bytes. The guest OS knows it can use 255 bytes from 0x00 and doesn't care/know where this memory physically
resides. Host OS now needs to find space for 255 bytes, either in one or multiple chunks in the physical memory. It can
map it as on the diagram to one big chunk or split it into multiple ones, as long as it can map guest request for its
`0x1E`-`0x20` to e.g. `0xF010`-`0xF012` and return the data.

---

#### Why do we need VT-d / AMD-Vi?
While mapping the memory (as described in the previous section) the host OS must take care of three things:
 1. When guest OS requests a page from memory using its (GPA) address it will get it from the HPA-addressed memory (=mapping)
 2. Memory of the guest cannot be touched by anything other than the guest (=protection)
 3. The process needs to be fast

While the first two are achievable with pure software emulation, it makes the memory access process slow as molasses 
since it can no longer rely on [DMA](https://en.wikipedia.org/wiki/Direct_memory_access) but involve CPU for every 
shifting bytes back and forth.   
Both VT-d and AMD-Vi allow to essentially instruct the hardware to do the mapping and enforce domains (security 
boundaries). In such case host OS simply needs to inform the hardware about the address to be translated on-the-fly. 
 
More on that can be found in the [Intel VT-d docs](https://software.intel.com/content/www/us/en/develop/articles/intel-virtualization-technology-for-directed-io-vt-d-enhancing-intel-platforms-for-efficient-virtualization-of-io-devices.html). 

---

#### How PCI/PCIe actually work?
Most people blindly plop `intel_iommu=on` and `iommu=pt` into their kernel line and get surprised when things don't 
work. I did too, so I started digging, which resulted in this whole repository.

Every device in the system has some memory reserved memory address space. It's used by the device and the the host 
system to communicate and exchange data. That reserved memory address is dictated by the firmware (i.e. BIOS) as both 
the device and OS must know it to communicate. In essence this is just slightly different than normal memory mapping. 
Here, you don't have just some OS using the memory but an OS **and** a device using the memory.  

Here's where [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) comes into play. In essence it's
able to remap GPA to HPA for both the OS and the device so that they can talk to each other. When device memory is 
remapped the guest OS talks to the hardware like it was really under some physical address it expects, while in reality 
the [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) moves the reserved region aperture 
somewhere else in the address space. This is *usually* fine.

---

#### RMRR - the monster in a closet
While both AMD and Intel allow for [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) remapping 
device's memory, Intel had an idea to introduce RMRR (Reserved Memory Region Reporting). In essence the firmware/BIOS 
publishes a list of regions where usage of [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) is 
ostensibly prohibited. The original intent for that feature was good, by allowing for USB keyboards to be automagically 
emulated by the USB controller itself before USB driver is loaded, like they were connected via PS/2. This also allow 
the GPU to display the picture before OS is loaded and even before [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) 
is initialized.  
However, it required some sacrifices: that memory should not be remapped as only OS and the device use the [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) 
and devices on the motherboard which may be communicating with e.g. the GPU pre-boot don't know anything about the 
mapping.  

However, one *undocumented assumption* was made: as soon as the driver is loaded the "out-of-band" access to the device
ends and the the OS takes over. However, *technically* the VT-d specification says that the RMRR is valid indefinitely.  

Linux for long time (up until [v3.17rc1](https://github.com/torvalds/linux/commit/c875d2c1b8083cd627ea0463e20bf22c2d7421ee))
didn't respect RMRR while setting up [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) 
resptcing that against-the-specs but ubiquitous assumption. This was an oversight as [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) 
API assumes exclusive control over the remapped address space. If such space is remapped the DMA access from outside of 
the [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) domain (i.e. from something else than the
host or VM guest OS, like a device on the motherboard) will fail which may lead to unpredictable results if the hardware
vendor didn't follow the *undocumented assumption*.  
  

Linux, as of now, excludes two specific classes of devices form being constricted by RMRR:
 - USB devices (as we historically trust they don't do weird things)
 - GPUs (unspoken rule that they're accessed out-of-band only before the driver loads)


RMRR *by itself* isn't evil, as long as it's used as [Intel's VT-d specification](https://software.intel.com/content/www/us/en/develop/download/intel-virtualization-technology-for-directed-io-architecture-specification.html)
intended - "*[RMRRs] that are either not DMA targets, or memory ranges that may be target of BIOS 
initiated DMA only during pre-boot phase (such as from a boot disk drive) **must not** be included in the reserved 
memory region reporting.*".

 
Intel anticipated the some will be tempted to misuse the feature as they warned in the VT-d specification: "*RMRR 
regions are expected to be used for legacy usages (...). Platform designers should avoid or limit use of reserved memory
 regions*".

----

#### What vendors did wrong?
HP (and probably others) decided to mark **every freaking PCI device memory space as RMRR!**<sup>`*`</sup> Like that, 
just in case... just that their tools could potentially maybe monitor these devices while OS agent is not installed. But 
wait, there's more! They marked **ALL** devices as such, even third party ones physically installed in motherboard's 
PCI/PCIe slots!

This in turn killed PCI passthrough for any of the devices in systems running Linux [>=3.17rc1](https://github.com/torvalds/linux/commit/c875d2c1b8083cd627ea0463e20bf22c2d7421ee).

*<small>`*` In case you skipped other sections above, RMRR is a special part of the memory which cannot be moved
to a VM.</small>*

---

### Other solutions & hacks

#### Contact your platform vendor
As the error suggests you can try to convince your vendor to fix the BIOS. If you do please create an issue in this repo 
to tell me about it, as this is **the only** real solution to the problem.

---

#### Use OS which ignores RMRRs
Some operating systems, notably [VMWare ESXi and vSphere](https://www.vmware.com/products/esxi-and-esx.html), are 
believed to ignore RMRRs (cannot be verified as they're closed-source). They're able to passthrough the devices without 
a problem, as long as you don't do something deliberately dangerous (see [Disclaimers](README.md#disclaimers)).

---

#### Attempt HPE's pseudofix (if you use HP)
To HPE's credit, they [recognized the problem and released an advisory with mitigations](https://support.hpe.com/hpesc/public/docDisplay?docId=emr_na-c04781229).
In short the HPE's solution is threefold:
 1. Fix the firmware to not include GPUs in RMRR
 2. Use System Configuration utility on Gen9+ servers to disable "HP Shared Memory features" on selected HPs cards
 3. Use their CLI BIOS/RBSU reconfiguration utility to set a special (invisible in menus) flags opting-out PCIe slots 
    from "smart monitoring"

However, we wouldn't be here if it actually worked as expected:
 - Fix 1 works only on GPUs and affects Linux 3.17-5.4 (as kernel has GPU exclusion since 5.4)
 - Fix 2 only works on *some* **external** HPE ethernet adapters with Gen9 and newer servers
 - Fix 3 theoretically works on all NICs, but not other cards (e.g. HBAs) and [doesn't actually work](https://community.hpe.com/t5/proliant-servers-netservers/microserver-gen8-quot-device-is-ineligible-for-iommu-domain/td-p/6947461#.X5D7SS9h1TY)
   (sic!) on some servers which are listed as affected (e.g. widely popular [HP/HPE Microserver Gen8](https://support.hpe.com/hpesc/public/docDisplay?docId=emr_na-c03793258))

Some tried [opening a support case](https://community.hpe.com/t5/proliant-servers-netservers/re-device-is-ineligible-for-iommu-domain-attach-due-to-platform/m-p/6817728/highlight/true#M21006) 
but the topic dried out. I tried [nagging HPE to fix the BIOS](https://community.hpe.com/t5/proliant-servers-ml-dl-sl/disabling-rmrds-rmrr-hp-shared-memory-features-on-microserver/td-p/7105623#.X5C0oy9h2uV).
Maybe there's a chance? Who knows... the future will show.

---

#### The comment-the-error-out hack (v3.17 - 5.3)
I was able to track the first mentions of this method to [a post by dschense on a German Proxmox forum](https://forum.proxmox.com/threads/hp-proliant-microserver-gen8-raidcontroller-hp-p410-passthrough-probleme.30547/post-155675) 
([en version](https://translate.googleusercontent.com/translate_c?depth=2&pto=aue&rurl=translate.google.com&sl=de&tl=en&u=https://forum.proxmox.com/threads/hp-proliant-microserver-gen8-raidcontroller-hp-p410-passthrough-probleme.30547/post-155675)).

In essence this was a logical conclusion: if you have an error comment it out and see what happens. It worked on the 
original protection being introduced in Linux v3.17. Unfortunately, the Linux v5.3 changed a lot (see [next section](deep-dive.md#long-term-solution---utilizing-relaxable-reservation-regions-317)).

---

#### Long-term solution - utilizing relaxable reservation regions (>=3.17)

##### Why commenting-out the error is a bad idea
Before Linux v5.3 RMRRs protection relied on [a simple patch introduced in v3.17](https://github.com/torvalds/linux/commit/c875d2c1b8083cd627ea0463e20bf22c2d7421ee)
 which excluded USB devices. [Commenting out the error](#the-comment-the-error-out-hack-v317---53) was a working 
 solution, as the kernel (including KVM subsystem) didn't care about the reserved regions.  

The situation changed dramatically. A large change aimed to [introduce IOVA list management](https://patchwork.kernel.org/project/kvm/cover/20190723160637.8384-1-shameerali.kolothum.thodi@huawei.com/) 
outside of the [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) driver was introduced. About 
the same time the RMRRs reserved memory [was split into two logical buckets](https://github.com/torvalds/linux/commit/1c5c59fbad20a63954de07687e4a29af18d1be12): 
absolutely-reserved (`IOMMU_RESV_DIRECT`) and so-called relaxed (`IOMMU_RESV_DIRECT_RELAXABLE`). USB devices and now 
GPUs were marked as *"relaxable"* as they were deemed safe to be remapped (even if against the VT-d specs and 
firmware's will). 


##### The kernel moves on quickly
Other subsystems naturally [started utilizing](https://github.com/torvalds/linux/commit/9b77e5c79840fc334a5b7f770c5ab0c09dc0e028)
that new IOVA interface, which broke the *"[comment-the-error-out](#the-comment-the-error-out-hack-v317---53)"* patch. 
Now with the [IOMMU](https://en.wikipedia.org/wiki/Input–output_memory_management_unit) error message commented out QEMU 
[will explode on vfio_dma_map()](https://bugs.launchpad.net/qemu/+bug/1869006/comments/14).  
Understandably, and for good reasons, [developers refuses to accommodate any requests to disable that](https://bugs.launchpad.net/qemu/+bug/1869006/comments/18). 
While even more checks can be commented-out and patched, as more subsystems in the kernel start relying on the IOVA 
lists management, it will be a cat-and-mouse game after every kernel release.


##### What this patch actually does
The path plugs into the same mechanism as the vanilla kernel used to [mark USB and GPUs as "relaxable"](https://github.com/torvalds/linux/commit/1c5c59fbad20a63954de07687e4a29af18d1be12).
This has three benefits:
 - The RMRR is not fully NULLified, as the memory is marked as reserved-with-exceptions and not just not reserved. This,
   combined with IOVA list management ensures that if some code somewhere needs to work differently with relaxable 
   devices it will work with this patch properly.
 - This patch doesn't introduce inconsistent state in the kernel. RMRRs are not hidden from the kernel by removal, nor
   ignored just in one place. This patch just changes the designation of these regions from `IOMMU_RESV_DIRECT` (*"we 
   know it's reserved and we will hold your hand"*) to [`IOMMU_RESV_DIRECT_RELAXABLE`](https://lore.kernel.org/patchwork/patch/1079954/) 
   (*"we know it's reserved but it's your playground"*).
 - It works across all affected kernels (v5.9.1 being the newest at the time of writing)

Additionally, this mechanism is [controllable with a boot option](README.md#configuration) making it safe and easy to 
disable as needed. 


##### Why kernel patch and not a loadable module?
Before taking this approach I poked around to see if the [IOMM driver](https://github.com/torvalds/linux/tree/master/drivers/iommu/intel) 
has any API around RMRR. It does not. The driver doesn't export any functions which can make the module feasible.  
While Linux >=5.3 has the IOVA list management interface, it is [being built by the Intel IOMMU driver](https://github.com/torvalds/linux/commit/1c5c59fbad20a63954de07687e4a29af18d1be12).
What it means is the hardcoded relaxable logic [decides about IOVA designation](https://github.com/torvalds/linux/commit/1c5c59fbad20a63954de07687e4a29af18d1be12#diff-e1fff7a2368c04e11696812359f854de9da431c63ec7c5a7bec8f6020e112a2aR2916).
Late on the same logic is [used for final sanity](https://github.com/torvalds/linux/blob/5f9e832c137075045d15cd6899ab0505cfb2ca4b/drivers/iommu/intel-iommu.c#L5057)  
independently from the state of the memory saved in the IOVA list. Only after this check passes the IOMMU mapping is
added.  

In other words even if >=5.4 [IOVA API is used to modify](https://github.com/torvalds/linux/commit/af029169b8fdae31064624d60b5469a3da95ad32) 
the assignment, the actual IOMU remapping will fail with *"Device is ineligible for IOMMU domain attach..."* error.


#### The future
It will be great if this patch could be upstreamed. However, I see slim-to-none chance of that happening, as this change
is prone to abuse. However, I will definitely try to communicate with kernel folks on how to proceed.
