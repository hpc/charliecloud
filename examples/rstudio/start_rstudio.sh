#!/bin/bash

#password=$(openssl rand -base64 16)
# Just use a basic password but in practice we'd want to create a random one like above
password=charliecloud
export RSTUDIO_PASSWORD=${password}

port=${1}
if [[ -z ${port} ]]; then
  echo "You must specify a port. Suggested range: 8000-9000"
  exit 1
fi

/usr/lib/rstudio-server/bin/rserver \
  --www-port="${port}" \
  --auth-none=0 \
  --auth-pam-helper-path=/rstudio/rstudio_auth \
  --auth-encrypt-password=0
