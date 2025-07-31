#!/bin/bash

mount --mkdir /dev/mapper/hammaroot-root /mnt/root
mount --mkdir /dev/mapper/hammaboot-boot /mnt/root/boot
mount --mkdir /dev/nvme0n1p1 /mnt/root/boot/EFI
mount --mkdir /dev/mapper/hammaroot-home /mnt/root/home
mount --mkdir /dev/mapper/hammaroot-var /mnt/root/var
