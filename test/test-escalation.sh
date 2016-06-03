#!/bin/bash

. tests.sh

echo
echo "### Testing escalation as euid=$EUID"

try setuid
