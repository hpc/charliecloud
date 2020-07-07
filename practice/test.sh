#!/bin/bash

./test ~/chorkshop/hello.sqfs
mount | grep -F fuse
ch-run /var/tmp/hello -- ./hello.py
fusermount -u /var/tmp/hello
mount | grep -F fuse
rm -rf /var/tmp/hello
