#!/bin/bash
if ["$1" == ""]; then
	echo "usage: ./test.sh <sqfs-filename>"
	echo "assumes that you have a sqfs file with this path: ~/chorkshop/<sqfs-filename>.sqfs"
	exit 1
fi

echo "CASE 1: No mount point specified, automount to /var/tmp, subdirectory /var/tmp/hello does not exist, mount does not exist"

rm -rf /var/tmp/$1
ls -l /var/tmp/$1
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=$HOME/chorkshop/hello.sqfs /var/tmp/hello -- ./hello.py"
./ch-run --squash=$HOME/chorkshop/$1.sqfs /var/tmp/$1 -- ./hello.py

echo "POST"
ls -l /var/tmp/$1
mount | grep -F fuse

echo "CLEANUP: remove directory"
rm -rf /var/tmp/$1



echo "---------------------------------------------------------------------------------------"



echo "CASE 2: mount point specified, subdirectory /var/tmp/chruntest does not exist, mount does not exist"

rm -rf /var/tmp/chruntest
ls -l /var/tmp/chruntest
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=$HOME/chorkshop/hello.sqfs:/var/tmp/chruntest /var/tmp/chruntest/ -- ./hello.py"
./ch-run --squash=$HOME/chorkshop/$1.sqfs:/var/tmp/chruntest /var/tmp/chruntest/ -- ./hello.py

echo "POST"
ls -l /var/tmp/chruntest
mount | grep -F fuse

echo "CLEANUP:remove directory"
rm -rf /var/tmp/chruntest



