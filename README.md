# 🍻 Relaxed RMRR Mapping for Linux 3.17+
## 🐧💨 Now you can use PCI passthrough on broken platforms

### TL;DR
When you try to use PCI/PCIe passthrough in KVM/QEMU/Proxmox you get:
```
vfio-pci 0000:01:00.1: Device is ineligible for IOMMU domain attach due to platform RMRR requirement. Contact your platform vendor.
```
followed by `vfio: failed to set iommu for container: Operation not permitted`.

This kernel patch fixes the problem **on kernels v3.17 and up** (tested up to 5.9.1). You can skip to "[Installation](README.md#installation)" 
section if you don't care about the rest. Reading of "[Disclaimers](README.md#disclaimers)" section to understand the 
risks, and "[Solutions & hacks](deep-dive.md#other-solutions--hacks)" to get the idea of different alternatives is 
highly recommended.

---

### Table of Contents
1. [Installation](README.md#installation)
    - [Proxmox - premade packages](README.md#proxmox---premade-packages)
    - [Proxmox - building from sources](README.md#proxmox---building-from-sources)
    - [Other distros](README.md#other-distros)
2. [Configuration](README.md#configuration)
3. [Deep Dive](deep-dive.md) - *a throughout research on the problem written for mortals*
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

### Installation

#### Proxmox - premade packages
As I believe in *[eating your own dog food](https://en.wikipedia.org/wiki/Eating_your_own_dog_food)* I run the kernel
described here. Thus, I publish precompiled packages.

1. Go to the [releases tab](https://github.com/kiler129/relax-intel-rmrr/releases/) and pick appropriate packages
2. Download all `*.deb`s packages to the server (you can copy links and use `wget https://...` on the server itself)
3. Install all using `dpkg -i *.deb` in the folder where you downloaded the debs
4. *(OPTIONAL)* Verify the kernel works with the patch disabled by rebooting and checking if `uname -r` shows a version 
   ending with `-pve-relaxablermrr`
5. [Configure the kernel](README.md#configuration)

---

#### Proxmox - building from sources
If you're running a version of Proxmox with [no packages available](README.md#proxmox---premade-packages) you can 
compile the kernel yourself using patches provided.

1. Prepare [at least 60GB of free disk space](https://forum.level1techs.com/t/linux-debian-proxmox-recompile-needing-over-60gb-and-counting-to-compile/160009)
2. Install required packages:
    ```shell script
    apt update
    apt install git nano screen patch fakeroot build-essential devscripts libncurses5 libncurses5-dev libssl-dev bc flex bison libelf-dev libaudit-dev libgtk2.0-dev libperl-dev asciidoc xmlto gnupg gnupg2 rsync lintian debhelper libdw-dev libnuma-dev libslang2-dev sphinx-common asciidoc-base automake cpio dh-python file gcc kmod libiberty-dev libpve-common-perl libtool perl-modules python-minimal sed tar zlib1g-dev lz4
    ```
3. Download everything:
    ```shell script
    mkdir new-kernel ; cd new-kernel
    git clone --depth=1 git://git.proxmox.com/git/pve-kernel.git
    git clone --depth=1 https://github.com/kiler129/relax-intel-rmrr.git
    ```
4. Add kernel patch & patch the toolchain
    ```shell script
    cd pve-kernel
    cp ../relax-intel-rmrr/patches/add-relaxable-rmrr-below-5_8.patch ./patches/kernel/CUSTOM-add-relaxable-rmrr.patch
    patch -p1 < ../relax-intel-rmrr/patches/proxmox.patch
    ```
5. Compile the kernel
    ```shell script
    make
    ```
This step will take a lot of time (30m-3h depending on your machine).

6. Install new kernel:
    ```shell script
    dpkg -i *.deb
    ```
7. *(OPTIONAL)* Verify the kernel works with the patch disabled by rebooting and checking if `uname -r` shows a version 
   ending with `-pve-relaxablermrr`
8. [Configure the kernel](README.md#configuration)

---

#### Other distros
1. Download kernel sources appropriate for your distribution
2. Apply an appropriate patch to the source tree
    - Go to the folder with your kernel source
    - For Linux 3.17 - 5.7: `patch -p1 < ../patches/add-relaxable-rmrr-below-5_8.patch`
    - For Linux >=5.8: `patch -p1 < ../patches/add-relaxable-rmrr-5_8_and_up.patch`
3. Follow your distro kernel compilation & installation instruction

***TODO:*** *Add automation script*

---

### Configuration
By default, after the kernel is installed, the patch will be *inactive* (i.e. the kernel will behave like this patch was
never applied). To activate it you have to add `intel_iommu=relax_rmrr` to your Linux boot args.

In most distros (including Proxmox) you do this by:
1. Opening `/etc/default/grub` (e.g. using `nano /etc/default/grub`)
2. Editing the `GRUB_CMDLINE_LINUX_DEFAULT` to include the option:
    - Example of old line:   
        ```
        GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt intremap=no_x2apic_optout"
        ```
    - Example of new line:
        ```
        GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on,relax_rmrr iommu=pt intremap=no_x2apic_optout"
        ```
    - *Side note: these are actually options which will make your PCI passthrough work and do so efficiently*
3. Running `update-grub`
4. Rebooting

To verify if the the patch is active execute `dmesg | grep 'Intel-IOMMU'` after reboot. You should see a result similar
 to this:
    ```
    root@sandbox:~# dmesg | grep 'Intel-IOMMU'
    [    0.050195] DMAR: Intel-IOMMU: assuming all RMRRs are relaxable. This can lead to instability or data loss
    root@sandbox:~# 
    ```

---

### Disclaimers
 - I'm not a kernel programmer by any means, so if I got something horribly wrong correct me please :)
 - This path should be safe, as long as you don't try to remap devices which are used by the IPMI/BIOS, e.g.
   - Network port shared between your IPMI and OS
   - RAID card in non-HBA mode with its driver loaded on the host
   - Network card with monitoring system installed on the host (e.g. [Intel Active Health System Agent](https://support.hpe.com/hpesc/public/docDisplay?docId=emr_na-c04781229))
 - This is not a supported solution by any of the vendors. In fact this is a direct violation of Intel's VT-d specs 
   (which Linux already violates anyway, but this is increasing the scope). It may cause crashes or major instabilities.
   You've been warned.

---

### Acknowledgments & References
 - [Comment-out hack research by dschense](https://forum.proxmox.com/threads/hp-proliant-microserver-gen8-raidcontroller-hp-p410-passthrough-probleme.30547/post-155675)
 - [Proxmox kernel compilation & patching by Feni](https://forum.proxmox.com/threads/compile-proxmox-ve-with-patched-intel-iommu-driver-to-remove-rmrr-check.36374/) 
 - [Linux IOMMU Support](https://www.kernel.org/doc/html/latest/x86/intel-iommu.html)
 - [RedHat RMRR EXCLUSION Whitepaper](https://access.redhat.com/sites/default/files/attachments/rmrr-wp1.pdf)
 - [Intel® Virtualization Technology for Directed I/O (VT-d)](https://software.intel.com/content/www/us/en/develop/articles/intel-virtualization-technology-for-directed-io-vt-d-enhancing-intel-platforms-for-efficient-virtualization-of-io-devices.html)
 - [Intel® Virtualization Technology for Directed I/O Architecture Specification](https://software.intel.com/content/www/us/en/develop/download/intel-virtualization-technology-for-directed-io-architecture-specification.html)
 
--- 
 
### License
This work (patches & docs) is dual-licensed under MIT and GPL 2.0 (or any later version), which should be treated as an 
equivalent of Linux `Dual MIT/GPL` (i.e. pick a license you prefer).
