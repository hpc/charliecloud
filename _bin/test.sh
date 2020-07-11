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



echo "CASE 2: mount point specified, subdirectory /var/tmp/chruntest exists, mount does not exist"

rm -rf /var/tmp/chruntest
mkdir /var/tmp/chruntest
ls -l /var/tmp/chruntest
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=$HOME/chorkshop/hello.sqfs:/var/tmp/chruntest /var/tmp/chruntest/hello -- ./hello.py"
./ch-run --squash=$HOME/chorkshop/hello.sqfs:/var/tmp/chruntest /var/tmp/chruntest/ -- ./hello.py

echo "POST"
ls -l /var/tmp/chruntest
ls -l /var/tmp/chruntest/hello
mount | grep -F fuse

echo "CLEANUP: unmount /var/tmp/chruntest/hello and remove directories"
fusermount -u /var/tmp/chruntest/hello
rm -rf /var/tmp/chruntest



