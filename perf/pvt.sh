#!/bin/bash

for i in {0..4}; do
    dd if=/dev/urandom of=tmpfile bs=1M count=1096
done
