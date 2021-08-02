#!/usr/bin/env bash
set -e

export PVE_KERNEL_BRANCH=master
export RELAX_INTEL_GIT_REPO="https://github.com/jamestutton/relax-intel-rmrr.git"
export RELAX_PATCH="add-relaxable-rmrr-5_11.patch"
export PROXMOX_PATCH="proxmox7.patch"

./build.sh