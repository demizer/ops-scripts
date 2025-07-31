#!/bin/bash

mdadm --create /dev/md0 --verbose --level=0 --raid-devices=2 /dev/nvme0n1p4 /dev/nvme1n1p4
mdadm --create /dev/md1 --verbose --level=1 --metadata=1.0 --raid-devices=2 /dev/nvme0n1p2 /dev/nvme1n1p2
