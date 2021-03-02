load ../common

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
}

@test 'ch-image cache chain-build' {
    run ch-image build --no-cache=ly-read -t first -f - . <<'eof'
from 00_tiny
run echo foo
run echo bar
run echo baz
eof
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $(echo "$output" | grep -Fc 'Adding layer') -eq 3 ]]

    run ch-image build -t first -f - . <<'EOF'
FROM first
RUN echo qux
EOF
   [[ $status -eq 0 ]]
   [[ $(echo "$output" | grep -Fc 'loaded from cache') -eq 3 ]]

}

@test 'ch-image cache cache_build' {
     run ch-image build --no-cache=ly-read -t first -f - . <<'eof'
from 00_tiny
run echo foo
run echo bar
run echo baz
eof
   echo "$output"
   [[ $status -eq 0 ]]

     run ch-image build --no-cache=ly-read -t first -f - . <<'eof'
from 00_tiny
run echo foo
run echo bar
run echo baz
eof
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $(echo "$output" | grep -Fc 'loaded from cache') -eq 3 ]]

}
