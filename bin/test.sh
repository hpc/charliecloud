#!/bin/bash

#############################################################################
# quick QA check                                                            #
#############################################################################

NAME=hello2
PATH=$HOME/chorkshop/hello2.sqfs



if ["$1" -eq ""]; then
	echo "usage: ./test.sh <sqfs-filename>"
	echo "assumes that you have a sqfs file with this path: ~/chorkshop/<sqfs-filename>.sqfs"
	exit 1
fi

echo "CASE 1: No mount point specified, automount to /var/tmp, subdirectory /var/tmp/hello does not exist, mount does not exist"

rm -rf /var/tmp/$1
ls -l /var/tmp/$1
mount | grep -F fuse

echo "CMDLINE:./ch-run $HOME/chorkshop/hello.sqfs -- ./hello.py"
./ch-run $HOME/chorkshop/$1.sqfs -- ./hello.py

echo "POST"
ls -l /var/tmp/$1
mount | grep -F fuse

echo "CLEANUP: none :)"



echo "---------------------------------------------------------------------------------------"



echo "CASE 2: mount point specified, subdirectory /var/tmp/chruntest does not exist, mount does not exist"

rm -rf /var/tmp/chruntest
ls -l /var/tmp/chruntest
mount | grep -F fuse

echo "CMDLINE:./ch-run --squash=/tmp/ $HOME/chorkshop/hello.sqfs -- ./hello.py"
./ch-run --squash=/tmp/ $HOME/chorkshop/$1.sqfs -- ./hello.py

echo "POST"
ls -l /tmp/$1
mount | grep -F fuse

echo "CLEANUP:none :)"


echo "----------------------------------------------------------------------------------------"

echo "CASE 3: original workflow"

./ch-mount $HOME/chorkshop/$1.sqfs /var/tmp
./ch-run /var/tmp/$1 -- ./hello.py
./ch-umount /var/tmp/$1
