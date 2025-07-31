#!/bin/bash

sgdisk -n 1:0:+300M -t 1:ef00 -c 1:"EFI System" /dev/nvme0n1
sgdisk -n 2:0:+2045M -t 2:fd00 -c 2:"BOOT" /dev/nvme0n1
sgdisk -n 3:0:+20G -t 3:fd00 -c 3:"SWAP" /dev/nvme0n1
sgdisk -n 4:0:0 -t 4:fd00 -c 4:"Linux RAID" /dev/nvme0n1
sfdisk -d /dev/nvme0n1 | sfdisk /dev/nvme1n1
