#!/usr/bin/env bash
set -e

export PVE_KERNEL_BRANCH=pve-kernel-5.13
export RELAX_INTEL_GIT_REPO="https://github.com/OrpheeGT/relax-intel-rmrr.git"
export RELAX_PATCH="add-relaxable-rmrr-5_13.patch"
export PROXMOX_PATCH="proxmox7.patch"

./build.sh
