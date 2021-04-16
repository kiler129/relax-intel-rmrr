## Proxmox - building from sources

If you're running a version of Proxmox with [no packages available](../../README.md#proxmox---premade-packages-easy), or
for some reason you don't/can't trust precompiled packages you can compile the kernel yourself using patches provided.

The easiest way to do it is to use a script provided in this repository, alongside this `README.md` file 
([`build/proxmox/build.sh`](build.sh))


### How to do it WITHOUT Docker?
This is mostly intended if you want to build & run on your Proxmox host. Jump to [Docker-ized](README.md#how-to-do-it-with-docker)
guide if you want to build packages in an isolated environment.

#### Prerequisites
1. Proxmox 6 install (recommended) or Debian Buster <small>*(it WILL fail on Ubuntu!)*</small>
2. Root access
3. ~30GB of free space

#### Steps
1. Download the [build script](build.sh) (e.g. use `wget https://raw.githubusercontent.com/kiler129/relax-intel-rmrr/master/build/proxmox/build.sh`)
2. Run the [`build.sh`](build.sh) script from terminal:  
   `RMRR_AUTOINSTALL=1 bash ./build.sh`  
   <small>*You can also manually execute commands in the script step-by-step. To facilitate that the script contains 
   extensive comments for every step.*</small>

4. *(OPTIONAL)* Verify the kernel works with the patch disabled by rebooting and checking if `uname -r` shows a version
   ending with `-pve-relaxablermrr`
5. [Configure the kernel](../../README.md#configuration)

This process will leave precompiled `*.deb` packages, in case you want to copy them to other Proxmox hosts you have.

---

### How to do it WITH Docker?
This is mostly intended for building packages for later use (and/or when you don't want to mess with your OS).

***TODO:** Currently the script will always build the newest `master` branch (so it's not suitable for CI).*

#### Prerequisites
1. Docker installed (tested on macOS & Debian 10)
2. ~30GB of free space
3. Copy of `Dockerfile` from `build/proxmox` (present alongside this `README`)

#### Steps

1. Build the container image *(this will build the kernel)*:  
   `docker build -t build-img -f Dockerfile .`
2. Create dummy container from image:  
   `docker create --name build-cont build-img`
3. Copy debs *(it will give you `debs` folder)*:
   `docker cp build-cont:/build/proxmox-kernel/debs ./`
4. Cleanup image & dummy container:  
   ```
   docker rm -f build-cont
   docker rmi -f build-img
   ```

Now you can [install debs like you would premade packages](../../README.md#proxmox---premade-packages-easy).
