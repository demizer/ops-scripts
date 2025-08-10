#!/bin/bash

mkfs.ext4 /dev/JesusALTVG/root
mkfs.ext4 /dev/JesusALTVG/home
mkfs.ext4 /dev/JesusALTVG/var
mkswap /dev/JesusALTVG/swap
mkfs.fat -F32 /dev/nvme0n1p2
mount /dev/JesusALTVG/root /mnt/root
mount --mkdir /dev/JesusALTVG/home /mnt/root/home
mount --mkdir /dev/JesusALTVG/var /mnt/root/var
mount --mkdir /dev/nvme0n1p2 /mnt/root/boot
