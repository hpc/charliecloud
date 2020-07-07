#!/bin/bash

./test ~/chorkshop/hello.sqfs /var/tmp/anna
mount | grep -F fuse
ch-run /var/tmp/anna -- ./hello.py
fusermount -u /var/tmp/anna
mount | grep -F fuse
