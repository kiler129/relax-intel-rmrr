#!/usr/bin/env bash
set -e

: "${PVE_KERNEL_BRANCH:=master}"
: "${RELAX_INTEL_GIT_REPO:=https://github.com/kiler129/relax-intel-rmrr.git}"
: "${PROXMOX_PATCH:=proxmox.patch}"
: "${RELAX_PATCH:=proxmox.patch}"

echo '###########################################################'
echo '################ Settings  ################################'
echo '###########################################################'

echo "PVE_KERNEL_BRANCH:${PVE_KERNEL_BRANCH}"
echo "RELAX_INTEL_GIT_REPO:${RELAX_INTEL_GIT_REPO}"
echo "PROXMOX_PATCH:${PROXMOX_PATCH}"
echo "RELAX_PATCH:${RELAX_PATCH}"


#################################################################################
# This script is a part of https://github.com/kiler129/relax-intel-rmrr project #
#################################################################################


echo '###########################################################'
echo '############# STEP 0 - PERFORM SANITY CHECKS ##############'
echo '###########################################################'
# Make sure script is working in the directory it is located in
cd "$(dirname "$(readlink -f "$0")")"

# Build process will fail if you're not a root (+ apt actions itself need it)
if [[ "$EUID" -ne 0 ]]
  then echo "This script should be run bash root"
  exit
fi

# Sanity check: make sure no two builds are started nor we have something leftover from previous attempts
if [[ -d "proxmox-kernel" ]]; then
  echo 'Directory "proxmox-kernel" already exists - if your previous build failed DELETE it first'
  exit 1
fi


echo '###########################################################'
echo '############ STEP 1 - INSTALL ALL DEPENDENCIES ############'
echo '###########################################################'
# Check if Proxmox-specific package exists in apt cache. If it does it means apt already knows Proxmox repository, if
# not we need to add it to properly build the kernel
if apt show libpve-common-perl &>/dev/null; then
  echo "Step 1.0: Proxmox repository already present - not adding"
else
  # Add Proxmox repo & their signing key
  echo "Step 1.0: Adding Proxmox apt repository..."
  apt -y update
  apt -y install gnupg
  # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7BF2812E8A6E88E0
  wget https://enterprise.proxmox.com/debian/proxmox-release-bullseye.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
  echo 'deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription' > /etc/apt/sources.list.d/pve.list
fi

# Install all packages required to build the kernel & create *.deb packages for installation
echo "Step 1.1: Installing build dependencies..."
apt -y update
apt -y install git nano screen patch fakeroot build-essential devscripts libncurses5 libncurses5-dev libssl-dev bc \
 flex bison libelf-dev libaudit-dev libgtk2.0-dev libperl-dev asciidoc xmlto gnupg gnupg2 rsync lintian debhelper \
 libdw-dev libnuma-dev libslang2-dev sphinx-common asciidoc-base automake cpio dh-python file gcc kmod libiberty-dev \
 libpve-common-perl libtool perl-modules python3-minimal sed tar zlib1g-dev lz4 curl zstd dwarves



echo '###########################################################'
echo '############ STEP 2 - DOWNLOAD CODE TO COMPILE ############'
echo '###########################################################'
# Create working directory
echo "Step 2.0: Creating working directory"
mkdir proxmox-kernel
cd proxmox-kernel

# Clone official Proxmox kernel repo & Relaxed RMRR Mapping patch
echo "Step 2.1: Downloading Proxmox kernel toolchain & patches"
git clone --depth=1 -b ${PVE_KERNEL_BRANCH} git://git.proxmox.com/git/pve-kernel.git
git clone --depth=1 ${RELAX_INTEL_GIT_REPO}

# Go to the actual Proxmox toolchain
cd pve-kernel

# (OPTIONAL) Download flat copy of Ubuntu hirsute kernel submodule
#  If you skip this the "make" of Proxmox kernel toolchain will download a copy (a Proxmox kernel is based on Ubuntu
#  If you skip this the "make" of Proxmox kernel toolchain will download a copy (a Proxmox kernel is based on Ubuntu
#  hirsute kernel). However, it will download it with the whole history etc which takes A LOT of space (and time). This
#  bypasses the process safely.
# This curl skips certificate validation because Proxmox GIT WebUI doesn't send Let's Encrypt intermediate cert
echo "Step 2.2: Downloading base kernel"
#TODO: This needs a proxmox7 fix
# curl -k "https://git.proxmox.com/?p=mirror_ubuntu-hirsute-kernel.git;a=snapshot;h=$(git submodule status submodules/ubuntu-hirsute | cut -c 2-41);sf=tgz" --output kernel.tgz
# tar -xf kernel.tgz -C submodules/ubuntu-hirsute/ --strip 1
# rm kernel.tgz



echo '###########################################################'
echo '################# STEP 3 - CREATE KERNEL ##################'
echo '###########################################################'
echo "Step 3.0: Applying patches"
cp ../relax-intel-rmrr/patches/${RELAX_PATCH} ./patches/kernel/CUSTOM-add-relaxable-rmrr.patch
patch -p1 < ../relax-intel-rmrr/patches/${PROXMOX_PATCH}


echo "Step 3.1: Compiling kernel... (it will take 30m-3h)"
# Note: DO NOT add -j to this make, see https://github.com/kiler129/relax-intel-rmrr/issues/1
# This step will compile kernel & build all *.deb packages as Proxmox builds internally
make


echo '###########################################################'
echo '################ STEP 4 - INSTALL KERNEL ##################'
echo '###########################################################'
echo "Step 4: Installing packages"

if [[ -v RMRR_AUTOINSTALL ]]; then
  apt install ./*.deb
else
  echo '=====>>>> SKIPPED - to enable autoinstallation set "RMRR_AUTOINSTALL" environment variable.'
  echo '=====>>>> To install execute "dpkg -i *.deb" after this script finishes'
fi

echo '###########################################################'
echo '################## STEP 5 - CLEANUP #######################'
echo '###########################################################'
# Remove all (~30GB) of stuff leftover after compilation
echo "Step 5: Cleaning up..."
cd ..
mkdir debs
mv pve-kernel/*.deb ./debs
rm -rf pve-kernel
rm -rf relax-intel-rmrr

exit 0
