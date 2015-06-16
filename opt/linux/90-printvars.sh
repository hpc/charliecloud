#!/bin/bash

. $(dirname $0)/charlie.sh
. $(dirname $0)/util.sh

set | egrep '^CH_'
