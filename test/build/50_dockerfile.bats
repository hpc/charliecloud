load ../common

@test 'Dockerfile: ARG and ENV' {

    # We use full scope for builders other than ch-grow because (1) with
    # ch-grow, we are responsible for --build-arg being implemented correctly
    # and (2) Docker and Buildah take a full minute for this test, vs. three
    # seconds for ch-grow.
    if [[ $CH_BUILDER = ch-grow ]]; then
        scope standard
    elif [[ $CH_BUILDER = none ]]; then
        skip 'no builder'
    else
        scope full
    fi
    prerequisites_ok argenv

    # Note that this test illustrates a number of behavior differences between
    # the builders. For most of these, but not all, Docker and Buildah have
    # the same behavior and ch-grow differs.

    echo '*** default (no --build-arg)'
    env_expected=$(cat <<'EOF'
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** one --build-arg, has no default'
    env_expected=$(cat <<'EOF'
chse_arg1_df=foo1
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg1_df=foo1 \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** one --build-arg, has default'
    env_expected=$(cat <<'EOF'
chse_arg2_df=foo2
chse_arg3_df=arg3 foo2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg2_df=foo2 \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** one --build-arg from environment'
    if [[ $CH_BUILDER == ch-grow ]]; then
        env_expected=$(cat <<'EOF'
chse_arg1_df=foo1
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    else
        # Docker and Buildah do not appear to take --build-arg values from the
        # environment. This is contrary to the "docker build" documentation;
        # "buildah bud" does not mention it either way. Tested on 18.09.7 and
        # 1.9.1-dev, respectively.
        env_expected=$(cat <<'EOF'
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    fi
    chse_arg1_df=foo1 \
    run ch-build --build-arg chse_arg1_df \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** one --build-arg set to empty string'
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
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** two --build-arg'
    env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=bar3
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg2_df=bar2 \
                 --build-arg chse_arg3_df=bar3 \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** repeated --build-arg'
    env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=arg3 bar2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run ch-build --build-arg chse_arg2_df=FOO \
                 --build-arg chse_arg2_df=bar2 \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** two --build-arg with substitution'
    if [[ $CH_BUILDER == ch-grow ]]; then
        env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=bar3 bar2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    else
        # Docker and Buildah don't substitute provided values.
        env_expected=$(cat <<'EOF'
chse_arg2_df=bar2
chse_arg3_df=bar3 ${chse_arg2_df}
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    fi
    # shellcheck disable=SC2016
    run ch-build --build-arg chse_arg2_df=bar2 \
                 --build-arg chse_arg3_df='bar3 ${chse_arg2_df}' \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** ARG not in Dockerfile'
    # Note: We don't test it, but for Buildah, the variable does show up in
    # the build environment.
    run ch-build --build-arg chse_doesnotexist=foo \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    if [[ $CH_BUILDER = ch-grow ]]; then
        [[ $status -eq 1 ]]
    else
        [[ $status -eq 0 ]]
    fi
    [[ $output = *'not consumed'* ]]
    [[ $output = *'chse_doesnotexist'* ]]

    echo '*** ARG not in environment'
    run ch-build --build-arg chse_arg1_df \
                 --no-cache -t argenv -f ./Dockerfile.argenv .
    echo "$output"
    if [[ $CH_BUILDER = ch-grow ]]; then
        [[ $status -eq 1 ]]
        [[ $output = *'--build-arg: chse_arg1_df: no value and not in environment'* ]]
    else
        [[ $status -eq 0 ]]
    fi
}

@test 'Dockerfile: COPY errors' {
    scope standard
    [[ $CH_BUILDER = none ]] && skip 'no builder'
    [[ $CH_BUILDER = buildah* ]] && skip 'Buildah untested'

    # Dockerfile on stdin, so no context directory.
    if [[ $CH_BUILDER != ch-grow ]]; then  # ch-grow doesn't support this yet
        run ch-build -t foo - <<EOF
FROM alpine:3.9
COPY doesnotexist .
EOF
        echo "$output"
        [[ $status -ne 0 ]]
        if [[ $CH_BUILDER = docker ]]; then
            # This error message seems wrong. I was expecting something about
            # no context, so COPY not allowed.
            [[ $output = *'no such file or directory'* ]]
        else
            false  # unimplemented
        fi
    fi

    # SRC not inside context directory.
    #
    # Case 1: leading "..".
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY ../foo .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'outside'*'context'* ]]
    # Case 2: ".." inside path.
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY foo/../../baz .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'outside'*'context'* ]]
    # Case 3: symlink leading outside context directory.
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY fixtures/symlink-to-tmp .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_BUILDER = docker ]]; then
        [[ $output = *'no such file or directory'* ]]
    else
        [[ $output = *'outside'*'context'* ]]
    fi

    # Multiple sources and non-directory destination.
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY Makefile Makefile.in /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY Makefile Makefile.in /etc/fstab
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY run /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY run /etc/fstab
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]

    # File not found.
    run ch-build -t foo -f - . <<EOF
FROM alpine:3.9
COPY doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_BUILDER = ch-grow ]]; then
        # This diagnostic is not fantastic, but it's what we got for now.
        [[ $output = *'no sources exist'* ]]
    else
        [[ $output = *'doesnotexist:'*'o such file or directory'* ]]
    fi
}
