# vim:set ft=dockerfile:

# This Dockerfile builds the newest kernel with RMRR patch
#
# TODO Add support for custom branch of build
FROM debian:bullseye

RUN mkdir -p /build
WORKDIR /build

RUN set -x \
  && apt update && apt install -y ca-certificates wget \
  && wget -O /build/build.sh 'https://raw.githubusercontent.com/kiler129/relax-intel-rmrr/master/build/proxmox/build.sh'

RUN apt -y update
RUN apt -y install git nano screen patch fakeroot build-essential devscripts libncurses5 libncurses5-dev libssl-dev bc \
 flex bison libelf-dev libaudit-dev libgtk2.0-dev libperl-dev asciidoc xmlto gnupg gnupg2 rsync lintian debhelper \
 libdw-dev libnuma-dev libslang2-dev sphinx-common asciidoc-base automake cpio dh-python file gcc kmod libiberty-dev \
 libtool perl-modules python3-minimal sed tar zlib1g-dev lz4 curl dwarves

#Need pahole 1.16 or above
RUN TEMP_DEB="$(mktemp)" && \
 wget -O "$TEMP_DEB" http://archive.ubuntu.com/ubuntu/pool/universe/d/dwarves-dfsg/dwarves_1.21-0ubuntu1~20.04_amd64.deb && \
 dpkg -i "$TEMP_DEB" && \
 rm -f "$TEMP_DEB" 


COPY *.sh /build/

RUN bash /build/build7.sh
