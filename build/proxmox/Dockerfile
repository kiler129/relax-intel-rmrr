# vim:set ft=dockerfile:

# This Dockerfile builds the newest kernel with RMRR patch
#
# TODO Add support for custom branch of build
FROM debian:buster

RUN mkdir -p /build
WORKDIR /build

RUN set -x \
  && apt update && apt install -y ca-certificates wget \
  && wget -O /build/build.sh 'https://raw.githubusercontent.com/kiler129/relax-intel-rmrr/master/build/proxmox/build.sh'

RUN bash /build/build.sh
