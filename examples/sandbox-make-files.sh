#!/bin/bash

# Set up the test directory for the Charliecloud sandbox test script. You must
# have sudo to use this script.

ROOTDIR=$1
ME=$2
YOU=$3

cd $ROOTDIR
if [ -e test ]; then
    echo "error: $ROOTDIR/test already exists"
    exit 1
fi
mkdir test
cd test

function dir_ () {
    mkdir $1
    chown $ME:$ME $1  # no-op if not root
    file_ $1/file
    chmod 660 $1/file
}

function file_ () {
    echo 'antidisestablishmentarianism' > $1
    chown $ME:$ME $1  # no-op if not root
}

function ln_ () {
    ln "$@"
    chown -h $ME:$ME $3  # no-op if not root
}

function x () {
    cmd=$1; shift
    user=$1; shift
    name=$1; shift
    perms=$1; shift
    expect=$1; shift
    if [ -n "$expect" ]; then
        name="$name.$perms~$expect"
    fi
    $cmd $@ $name
    if [ -n "$perms" ]; then
        chmod $perms $name
        if [ $user != $ME ]; then
            sudo chown $user $name
        fi
    fi
}

x dir_ $ME  nopass    770
cd nopass
x dir_  $ME    dir    770
cd ..

x dir_  $ME  pass     770

cd pass
x dir_  $ME    me-d   000 ---
x dir_  $ME    me-d   100 --t
x dir_  $ME    me-d   400 r--
x dir_  $ME    me-d   500 r-t
x dir_  $ME    me-d   700 rwt

x file_ $ME    me-f   000 ---
x file_ $ME    me-f   400 r--
x file_ $ME    me-f   600 rw-

x dir_  $YOU   you-d  700 ---
x dir_  $YOU   you-d  710 --t
x dir_  $YOU   you-d  740 r--
x dir_  $YOU   you-d  750 r-t
x dir_  $YOU   you-d  770 rwt

x file_ $YOU   you-f  440 r--
x file_ $YOU   you-f  600 ---
x file_ $YOU   you-f  660 rw-


# Links last to make sure targets exist.
x ln_   $ME    lin-dir     ''  rwt -s me-d.700*
x ln_   $ME    lin-file    ''  rw- -s me-f.600*
x ln_   $ME    lout-dira   ''  --- -s $ROOTDIR/test/nopass/dir
x ln_   $ME    lout-dirr   ''  --- -s ../nopass/dir
x ln_   $ME    lout-filea  ''  --- -s $ROOTDIR/test/nopass/file
x ln_   $ME    lout-filer  ''  --- -s ../nopass/file

