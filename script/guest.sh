#!/bin/sh -e

if [ -n "$TMP" ]; then
    mkdir -p "$TMP"
fi


echo minesvm > /etc/hostname

apt-get install -y grub2 linux-image-generic
