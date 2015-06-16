#!/bin/sh

# Simple hello world job

echo 'hello world on stdout'
echo 'hello world on stderr' >&2
echo -n 'id: '
id
echo -n 'whoami: '
whoami

# show Charliecloud environment variables
set | egrep '^\s*CH_'

echo
echo "sleeping for 5 seconds"
sleep 5
echo 'done sleeping'
