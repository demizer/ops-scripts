#!/bin/bash

mkfs.vfat -F32 /dev/nvme0n1p1
mkfs.vfat -F32 /dev/nvme1n1p1
mkfs.ext4 /dev/mapper/hammaboot-boot
mkfs.ext4 /dev/mapper/hammaroot-root 
mkfs.ext4 /dev/mapper/hammaroot-home
mkfs.ext4 /dev/mapper/hammaroot-var
mkswap /dev/nvme0n1p3
mkswap /dev/nvme1n1p3
swapon /dev/nvme0n1p3
swapon /dev/nvme1n1p3
