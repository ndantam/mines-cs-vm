#!/bin/sh -e

if [ -n "$TMP" ]; then
    mkdir -p "$TMP"
fi

apt-get -y update
apt-get -y upgrade


# cat /tmp/debconf-selections | debconf-set-selections


echo minesvm > /etc/hostname

apt-get install -y grub2 linux-image-generic linux-headers-generic
