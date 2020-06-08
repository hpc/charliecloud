#!/bin/bash

# This script is a wrapper used by automake. It should never be used manually.

bindir=../bin

set -e

"./${bindir}/ch-test" all -b none \
    "--pack-dir=/tmp/ch-test.tmp.${USER}/tar" \
    "--img-dir=/tmp/ch-test.tmp.${USER}/img"
