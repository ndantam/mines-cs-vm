#!/bin/sh -e

if [ -n "$TMP" ]; then
    mkdir -p "$TMP"
fi

debconf-set-selections /tmp/debconf-selections
dpkg-reconfigure -fnoninteractive gdm3

echo minesvm > /etc/hostname

apt-get install -y grub2 linux-image-generic linux-headers-generic
