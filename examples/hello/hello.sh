#!/bin/sh

set -e

cd $(dirname $0)
. ./util.sh

echo 'Hello world!'
print_info
echo 'OK'
