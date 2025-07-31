#!/bin/bash

pvcreate /dev/md0
pvcreate /dev/md1

vgcreate hammaroot /dev/md0
vgcreate hammaboot /dev/md1

lvcreate -n root -L 60g hammaroot
lvcreate -n var -L 150G hammaroot
lvcreate -n home -l 100%FREE hammaroot
lvcreate -n boot -l 100%FREE hammaboot
