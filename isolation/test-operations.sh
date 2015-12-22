#!/bin/bash

. tests.sh

echo
echo "### Testing operations as euid=$EUID"

try chroot_escape
