load ../common

@test 'ch-build --builder-info' {
    scope standard
    ch-build --builder-info
}

@test 'ch-build docker metadata' {

    scope standard
    [[ $CH_BUILDER = docker ]] || skip 'We only test docker metadata'
    tag=metadata
    run ch-build -t "$tag" -f - . <<'EOF'
FROM 00_tiny
RUN echo hello
EOF
    run ch-builder2tar "$tag" "$ch_tardir"
    tar -xf "$ch_tardir"/"$tag".tar.gz ch/metadata.json --strip-components 1
    diff -u - "$tag.json" <<'EOF'
{
  "arch": "amd64",
  "cwd": "",
  "env": {
    "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  },
  "labels": {},  
  "shell": ["|0","/bin/sh","-c","echo hello"],
  "volumes": []
}
EOF
}

@test 'sotest executable works' {
    scope quick
    export LD_LIBRARY_PATH=./sotest
    ldd sotest/sotest
    sotest/sotest
}
