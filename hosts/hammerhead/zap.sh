#!/bin/bash

mdadm --zero-superblock /dev/nvme0n1p1 /dev/nvme1n1p1
mdadm --zero-superblock /dev/nvme0n1p2 /dev/nvme1n1p2
mdadm --zero-superblock /dev/nvme0n1p3 /dev/nvme1n1p3
mdadm --zero-superblock /dev/nvme0n1p4 /dev/nvme1n1p4
