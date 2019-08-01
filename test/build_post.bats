load common

@test 'ARG and ENV' {
    scope standard
    prerequisites_ok argenv

    # default (no --build-arg)
    env_expected=$(cat <<'EOF'
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # one --build-arg, has no default
    env_expected=$(cat <<'EOF'
chse_arg1_df=foo1
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg1_df=foo1 \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # one --build-arg, has default
    env_expected=$(cat <<'EOF'
chse_arg2_df=foo2
chse_arg3_df=arg3 foo2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg2_df=foo2 \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # one --build-arg from environment
    env_expected=$(cat <<'EOF'
chse_arg1_df=foo1
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    chse_arg1_df=foo1 \
    run ch-build --build-arg chse_arg1_df \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # one --build-arg set to empty string
    env_expected=$(cat <<'EOF'
chse_arg1_df=
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    chse_arg1_df=foo1 \
    run ch-build --build-arg chse_arg1_df= \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # two --build-arg
    env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=bar3
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg2_df=bar2 \
                 --build-arg chse_arg3_df=bar3 \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # two --build-arg with substitution
    env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=bar3 bar2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    # shellcheck disable=SC2016
    run ch-build --build-arg chse_arg2_df=bar2 \
                 --build-arg chse_arg3_df='bar3 ${chse_arg2_df}' \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    # ARG not in Dockerfile
    run ch-build --build-arg chse_doesnotexist=foo \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--build-arg: not consumed: chse_doesnotexist'* ]]

    # ARG not in environment
    run ch-build --build-arg chse_arg1_df \
                 -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--build-arg: chse_arg1_df: no value and not in environment'* ]]
}

@test 'nothing unexpected in tarball directory' {
    scope quick
    run find "$ch_tardir" -mindepth 1 -maxdepth 1 \
        -not \(    -name '_ch-grow' \
                -o -name '*.sqfs' \
                -o -name '*.tar.gz' \
                -o -name '*.tar.xz' \
                -o -name '*.pq_missing' \)
    echo "$output"
    [[ $output = '' ]]
}
