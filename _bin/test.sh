#!/bin/bash

echo "CASE 1: No mount point specified, automount to /var/tmp, subdirectory /var/tmp/hello does not exist, mount does not exist"

ls -l /var/tmp/hello
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=$HOME/chorkshop/hello.sqfs /var/tmp/hello -- ./hello.py"
./ch-run --squash=$HOME/chorkshop/hello.sqfs /var/tmp/hello -- ./hello.py

echo "POST"
ls -l /var/tmp/hello
mount | grep -F fuse

echo "CLEANUP: unount /var/tmp/hello and remove directory"
fusermount -u /var/tmp/hello
rm -rf /var/tmp/hello



echo "---------------------------------------------------------------------------------------"



echo "CASE 2: mount point specified, subdirectory /var/tmp/anna exists, mount does not exist"

rm -rf /var/tmp/anna
mkdir /var/tmp/anna
ls -l /var/tmp/anna
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=$HOME/chorkshop/hello.sqfs:/var/tmp/anna /var/tmp/anna/hello -- ./hello.py"
./ch-run --squash=$HOME/chorkshop/hello.sqfs:/var/tmp/anna /var/tmp/anna/hello -- ./hello.py

echo "POST"
ls -l /var/tmp/anna
ls -l /var/tmp/anna/hello
mount | grep -F fuse

echo "CLEANUP: unmount /var/tmp/anna/hello and remove directories"
fusermount -u /var/tmp/anna/hello
rm -rf /var/tmp/anna
