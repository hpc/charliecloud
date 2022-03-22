load ../common


@test 'Dockerfile: syntax quirks' {
    # These should all yield an output image, but we don't actually care about
    # it, so re-use the same one.

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only' # FIXME: other builders?

    # No newline at end of file.
      printf 'FROM 00_tiny\nRUN echo hello' \
    | ch-image build -t syntax-quirks -f - .

    # Newline before FROM.
    ch-image build -t syntax-quirks -f - . <<'EOF'

FROM 00_tiny
RUN echo hello
EOF

    # Comment before FROM.
    ch-image build -t tmpimg -f - . <<'EOF'
# foo
FROM 00_tiny
RUN echo hello
EOF

    # Single instruction.
    ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
EOF

    # Whitespace around comment hash.
    run ch-image -v build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
#no whitespace
 #before only
# after only
 # both before and after
  # multiple before
	# tab before
EOF

    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'comment') -eq 6 ]]

    # Whitespace and newlines (turn on whitespace highlighting in your editor):
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny

# trailing whitespace: shell sees it verbatim
RUN true 

# whitespace-only line: ignored
 
# two in a row
 
 

# line continuation, no whitespace: shell sees one word
RUN echo test1\
a
# two in a row
RUN echo test1\
b\
c

# whitespace before line continuation: shell sees whitespace verbatim
RUN echo test2  \
a
# two in a row
RUN echo test2  \
b  \
c

# whitespace after line continuation: shell sees one word
RUN echo test3\  
a
# two in a row
RUN echo test3\  
b\  
c

# whitespace before & after line continuation: shell sees before only
RUN echo test4   \  
a
# two in a row
RUN echo test4   \  
b   \  
c

# whitespace on continued line: shell sees continued line's whitespace
RUN echo test5\
  a
# two in a row
RUN echo test5\
  b\
  c

# whitespace-only continued line: shell sees whitespace verbatim
RUN echo test6\
  \
a
# two in a row
RUN echo test6\
  \
  \
b

# backslash that is not a continuation: shell sees it verbatim
RUN echo test\ 7\
a
# two in a row
RUN echo test\ 7\ \
b
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    output_expected=$(cat <<'EOF'
warning: not yet supported, ignored: issue #777: .dockerignore file
  1 FROM 00_tiny
  4 RUN ['/bin/sh', '-c', 'true ']
 13 RUN ['/bin/sh', '-c', 'echo test1a']
test1a
 16 RUN ['/bin/sh', '-c', 'echo test1bc']
test1bc
 21 RUN ['/bin/sh', '-c', 'echo test2  a']
test2 a
 24 RUN ['/bin/sh', '-c', 'echo test2  b  c']
test2 b c
 29 RUN ['/bin/sh', '-c', 'echo test3a']
test3a
 32 RUN ['/bin/sh', '-c', 'echo test3bc']
test3bc
 37 RUN ['/bin/sh', '-c', 'echo test4   a']
test4 a
 40 RUN ['/bin/sh', '-c', 'echo test4   b   c']
test4 b c
 45 RUN ['/bin/sh', '-c', 'echo test5  a']
test5 a
 48 RUN ['/bin/sh', '-c', 'echo test5  b  c']
test5 b c
 53 RUN ['/bin/sh', '-c', 'echo test6  a']
test6 a
 57 RUN ['/bin/sh', '-c', 'echo test6    b']
test6 b
 63 RUN ['/bin/sh', '-c', 'echo test\\ 7a']
test 7a
 66 RUN ['/bin/sh', '-c', 'echo test\\ 7\\ b']
test 7 b
grown in 16 instructions: tmpimg
EOF
)
    diff -u <(echo "$output_expected") <(echo "$output")
}


@test 'Dockerfile: syntax errors' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # Bad instruction. Also, -v should give interal blabber about the grammar.
    run ch-image -v build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
WEIRDAL
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # error message
    [[ $output = *"can't parse: -:2,1"* ]]
    # internal blabber (varies by version)
    [[ $output = *'No terminal'*"'W'"*'at line 2 col 1'* ]]

    # Bad long option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --chown= foo bar
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't parse: -:2,14"* ]]

    # Empty input.
    run ch-image build -t tmpimg -f /dev/null .
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no instructions found: /dev/null'* ]]

    # Newline only.
    run ch-image build -t tmpimg -f - . <<'EOF'

EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no instructions found: -'* ]]

    # Comment only.
    run ch-image build -t tmpimg -f - . <<'EOF'
# foo
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no instructions found: -'* ]]

    # Only newline, then comment.
    run ch-image build -t tmpimg -f - . <<'EOF'

# foo
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no instructions found: -'* ]]

    # Non-ARG instruction before FROM
    run ch-image build -t tmpimg -f - . <<'EOF'
RUN echo uh oh
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'first instruction must be ARG or FROM'* ]]
}


@test 'Dockerfile: semantic errors' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # Repeated instruction option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --chown=foo --chown=bar fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'  2 COPY: repeated option --chown'* ]]

    # COPY invalid option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --foo=foo fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'COPY: invalid option --foo'* ]]

    # FROM invalid option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM --foo=bar 00_tiny
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'FROM: invalid option --foo'* ]]
}


@test 'Dockerfile: not-yet-supported features' {
    # This test also creates images we don't care about.

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # ARG before FROM
    run ch-image build -t tmpimg -f - . <<'EOF'
ARG foo=bar
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: ARG before FROM not yet supported; see issue #779'* ]]

    # FROM --platform
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM --platform=foo 00_tiny
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #778: FROM --platform'* ]]

    # other instructions
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
ADD foo
CMD foo
ENTRYPOINT foo
LABEL foo
ONBUILD foo
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Ec 'not yet supported.+instruction') -eq 5 ]]
    [[ $output = *'warning: not yet supported, ignored: issue #782: ADD instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #780: CMD instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #780: ENTRYPOINT instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #781: LABEL instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #788: ONBUILD instruction'* ]]

    # .dockerignore files
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not yet supported, ignored: issue #777: .dockerignore file'* ]]

    # URL (Git repo) contexts
    run ch-image build -t not-yet-supported -f - \
        git@github.com:hpc/charliecloud.git <<'EOF'
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #773: URL context'* ]]
    run ch-image build -t tmpimg -f - \
        https://github.com/hpc/charliecloud.git <<'EOF'
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #773: URL context'* ]]

    # variable expansion modifiers
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
ARG foo=README
COPY fixtures/${foo:+bar} .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'error: modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)'* ]]
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
ARG foo=README
COPY fixtures/${foo:-bar} .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'error: modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)'* ]]
}


@test 'Dockerfile: unsupported features' {
    # This test also creates images we don't care about.

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # parser directives
    run ch-image build -t tmpimg -f - . <<'EOF'
# escape=foo
# syntax=foo
#syntax=foo
 # syntax=foo
 #syntax=foo
# foo=bar
# comment
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not supported, ignored: parser directives'* ]]
    [[ $(echo "$output" | grep -Fc 'parser directives') -eq 5 ]]

    # COPY --from
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --chown=foo fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not supported, ignored: COPY --chown'* ]]

    # Unsupported instructions
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
EXPOSE foo
HEALTHCHECK foo
MAINTAINER foo
STOPSIGNAL foo
USER foo
VOLUME foo
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'not supported') -eq 6 ]]
    [[ $output = *'warning: not supported, ignored: EXPOSE instruction'* ]]
    [[ $output = *'warning: not supported, ignored: HEALTHCHECK instruction'* ]]
    [[ $output = *'warning: not supported, ignored: MAINTAINER instruction'* ]]
    [[ $output = *'warning: not supported, ignored: STOPSIGNAL instruction'* ]]
    [[ $output = *'warning: not supported, ignored: USER instruction'* ]]
    [[ $output = *'warning: not supported, ignored: VOLUME instruction'* ]]
}


@test 'Dockerfile: ENV parsing' {
    scope standard
    [[ $CH_TEST_BUILDER = none ]] && skip 'no builder'

    env_expected=$(cat <<'EOF'
('chse_0a', 'value 0a')
('chse_0b', 'value 0b')
('chse_1b', 'value 1b ')
('chse_2a', 'value2a')
('chse_2b', 'value2b')
('chse_2c', 'chse2: value2a')
('chse_2d', 'chse2: value2a')
('chse_3a', '"value3a"')
('chse_4a', 'value4a')
('chse_4b', 'value4b')
('chse_5a', 'value5a')
('chse_5b', 'value5b')
('chse_6a', 'value6a')
('chse_6b', 'value6b')
EOF
)
    run build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM centos8

# FIXME: make this more comprehensive, e.g. space-separate vs.
# equals-separated for everything.

# Value has internal space.
ENV chse_0a value 0a
ENV chse_0b="value 0b"

# Value has internal space and trailing space. NOTE: Beware your editor
# "helpfully" removing the trailing space.
#
# FIXME: Docker removes the trailing space!
#ENV chse_1a value 1a 
ENV chse_1b="value 1b "
# FIXME: currently a parse error.
#ENV chse_1c=value\ 1c\ 

# Value surrounded by double quotes, which are not part of the value.
ENV chse_2a "value2a"
ENV chse_2b="value2b"

# Substitute previous value, space-separated, without quotes.
ENV chse_2c chse2: ${chse_2a}

# Substitute a previous value, equals-separated, with quotes.
ENV chse_2d="chse2: ${chse_2a}"

# Backslashed quotes are included in value.
ENV chse_3a \"value3a\"
# FIXME: backslashes end up literal
#ENV chse_3b=\"value3b\"

# Multiple variables in the same instruction.
ENV chse_4a=value4a chse_5a=value5a
ENV chse_4b=value4b \
    chse_5b=value5b

# Value contains line continuation. FIXME: I think something isn't quite right
# here. The backslash, newline sequence appears in the parse tree but not in
# the output. That doesn't seem right.
ENV chse_6a value\
6a
ENV chse_6b "value\
6b"

# FIXME: currently a parse error.
#ENV chse_4=value4 chse_5="value5 foo" chse_6=value6\ foo chse_7=\"value7\"

# Print output with Python to avoid ambiguity.
RUN python3 -c 'import os; [print((k,v)) for (k,v) in sorted(os.environ.items()) if "chse_" in k]'
EOF
  echo "$output"
  [[ $status -eq 0 ]]
  diff -u <(echo "$env_expected") <(echo "$output" | grep -E "^\('chse_")
}


@test 'Dockerfile: SHELL' {
   scope standard
   [[ $CH_TEST_BUILDER = none ]] && skip 'no builder'
   [[ $CH_TEST_BUILDER = buildah* ]] && skip "Buildah doesn't support SHELL"

   # test that SHELL command can change executables and parameters
   run build_ -t tmpimg --no-cache -f - . <<'EOF'
FROM 00_tiny
RUN echo default: $0
SHELL ["/bin/ash", "-c"]
RUN echo ash: $0
SHELL ["/bin/sh", "-v", "-c"]
RUN echo sh-v: $0
EOF
   echo "$output"
   [[ $status -eq 0 ]]
   [[ $output = *"default: /bin/sh"* ]]
   [[ $output = *"ash: /bin/ash"* ]]
   [[ $output = *"sh-v: /bin/sh"* ]]

   # test that it fails if shell doesn't exist
   run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
SHELL ["/doesnotexist", "-c"]
RUN print("hello")
EOF
   echo "$output"
   [[ $status -eq 1 ]]
   if [[ $CH_TEST_BUILDER = ch-image ]]; then
      [[ $output = *"/doesnotexist: No such file or directory"* ]]
   else
      [[ $output = *"/doesnotexist: no such file or directory"* ]]
   fi

   # test that it fails if no paramaters
   run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
SHELL ["/bin/sh"]
RUN true
EOF
   echo "$output"
   [[ $status -ne 0 ]] # different builders use different error exit codes
   [[ $output = *"/bin/sh: can't open 'true': No such file or directory"* ]]

   # test that it works with python3
   run build_ -t tmpimg -f - . <<'EOF'
FROM centos7
SHELL ["/usr/bin/python3", "-c"]
RUN print ("hello")
EOF
   echo "$output"
   [[ $status -eq 0 ]]
   if [[ $CH_TEST_BUILDER = ch-image ]]; then
      [[ $output = *"grown in 3 instructions: tmpimg"* ]]
   else
      [[ $output = *"Successfully built"* ]]
   fi
}


@test 'Dockerfile: ARG and ENV values' {
    # We use full scope for builders other than ch-image because (1) with
    # ch-image, we are responsible for --build-arg being implemented correctly
    # and (2) Docker and Buildah take a full minute for this test, vs. three
    # seconds for ch-image.
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        scope standard
    elif [[ $CH_TEST_BUILDER = none ]]; then
        skip 'no builder'
    else
        scope full
    fi
    prerequisites_ok argenv

    # Note that this test illustrates a number of behavior differences between
    # the builders. For most of these, but not all, Docker and Buildah have
    # the same behavior and ch-image differs.

    echo '*** default (no --build-arg)'
    env_expected=$(cat <<'EOF'
chse_arg2_df=arg2
chse_arg3_df=arg3 arg2
chse_env1_df=env1
chse_env2_df=env2 env1
EOF
)
    run build_ --no-cache -t tmpimg -f ./Dockerfile.argenv .
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
    run build_ --build-arg chse_arg1_df=foo1 \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
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
    run build_ --build-arg chse_arg2_df=foo2 \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** one --build-arg from environment'
    if [[ $CH_TEST_BUILDER == ch-image ]]; then
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
    run build_ --build-arg chse_arg1_df \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
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
    run build_ --build-arg chse_arg1_df= \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
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
    run build_ --build-arg chse_arg2_df=bar2 \
               --build-arg chse_arg3_df=bar3 \
                 --no-cache -t tmpimg -f ./Dockerfile.argenv .
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
    run build_ --build-arg chse_arg2_df=FOO \
               --build-arg chse_arg2_df=bar2 \
                 --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** two --build-arg with substitution'
    if [[ $CH_TEST_BUILDER == ch-image ]]; then
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
    run build_ --build-arg chse_arg2_df=bar2 \
               --build-arg chse_arg3_df='bar3 ${chse_arg2_df}' \
                 --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    [[ $status -eq 0 ]]
    env_actual=$(echo "$output" | grep -E '^chse_')
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** ARG not in Dockerfile'
    # Note: We don't test it, but for Buildah, the variable does show up in
    # the build environment.
    run build_ --build-arg chse_doesnotexist=foo \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $status -eq 1 ]]
    else
        [[ $status -eq 0 ]]
    fi
    [[ $output = *'not consumed'* ]]
    [[ $output = *'chse_doesnotexist'* ]]

    echo '*** ARG not in environment'
    run build_ --build-arg chse_arg1_df \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $status -eq 1 ]]
        [[ $output = *'--build-arg: chse_arg1_df: no value and not in environment'* ]]
    else
        [[ $status -eq 0 ]]
    fi
}

@test 'Dockerfile: COPY list form' {
    scope standard
    [[ $CH_TEST_BUILDER == ch-image ]] || skip 'ch-image only'

    # single source
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY ["fixtures/empty-file", "."]
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"COPY ['fixtures/empty-file'] -> '.'"* ]]
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/empty-file

    # multiple source
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY ["fixtures/empty-file", "fixtures/README", "."]
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"COPY ['fixtures/empty-file', 'fixtures/README'] -> '.'"* ]]
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/empty-file
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/README
}

@test 'Dockerfile: COPY errors' {
    scope standard
    [[ $CH_TEST_BUILDER = none ]] && skip 'no builder'
    [[ $CH_TEST_BUILDER = buildah* ]] && skip 'Buildah untested'

    # Dockerfile on stdin, so no context directory.
    run build_ -t tmpimg - <<'EOF'
FROM 00_tiny
COPY doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        # This error message seems wrong. I was expecting something about
        # no context, so COPY not allowed.
        [[ $output = *'file does not exist'* ]]
    else
        [[ $output = *'no context'* ]]
    fi

    # SRC not inside context directory.
    #
    # Case 1: leading "..".
    run build_ -t tmpimg -f - sotest <<'EOF'
FROM 00_tiny
COPY ../common.bash .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'outside'*'context'* ]]
    # Case 2: ".." inside path.
    run build_ -t tmpimg -f - sotest <<'EOF'
FROM 00_tiny
COPY lib/../../common.bash .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'outside'*'context'* ]]
    # Case 3: symlink leading outside context directory.
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY fixtures/symlink-to-tmp .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        [[ $output = *'file does not exist'* ]]
    else
        [[ $output = *'outside'*'context'* ]]
    fi

    # Multiple sources and non-directory destination.
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY Build.missing common.bash /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run build_ -t foo -f - . <<'EOF'
FROM 00_tiny
COPY Build.missing common.bash /etc/fstab
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        [[ $output = *'must be a directory'* ]]
    else
        [[ $output = *'not a directory'* ]]
    fi
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY run /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY run /etc/fstab
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]

    # No sources given.
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *"error: can't parse: -:2,7"* ]]
    else
        [[ $output = *'COPY requires at least two arguments'* ]]
    fi
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY ["."]
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *"error: can't COPY: must specify at least one source"* ]]
    else
        [[ $output = *'COPY requires at least two arguments'* ]]
    fi

    # No sources found.
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not found'* ]]

    # Some sources found.
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY fixtures/README doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not found'* ]]

    # No context with Dockerfile on stdin by context "-"
    run build_ -t tmpimg - <<'EOF'
FROM 00_tiny
COPY fixtures/README .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *"error: can't COPY: no context because \"-\" given"* ]]
    else
        [[ $output = *'COPY failed: file not found in build context or'* ]]
    fi
}


@test 'Dockerfile: COPY --from errors' {
    scope standard
    [[ $CH_TEST_BUILDER = none ]] && skip 'no builder'
    [[ $CH_TEST_BUILDER = buildah* ]] && skip 'Buildah untested'

    # Note: Docker treats several types of erroneous --from names as another
    # image and tries to pull it. To avoid clashes with real, pullable images,
    # we use the random name "uhigtsbjmfps" (https://www.random.org/strings/).

    # current index
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=0 /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'current'*'stage'* ]]

    # current name
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny AS uhigtsbjmfps
COPY --from=uhigtsbjmfps /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'current stage'* ]]
            ;;
        docker)
            [[ $output = *'pull access denied'*'repository does not exist'* ]]
            ;;
        *)
            false
            ;;
    esac

    # index does not exist
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=1 /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'does not exist'* ]]
            ;;
        docker)
            [[ $output = *'index out of bounds'* ]]
            ;;
        *)
            false
            ;;
    esac

    # name does not exist
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=uhigtsbjmfps /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'does not exist'* ]]
            ;;
        docker)
            [[ $output = *'pull access denied'*'repository does not exist'* ]]
            ;;
        *)
            false
            ;;
    esac

    # index exists, but is later
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=1 /etc/fstab /
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'does not exist yet'* ]]
            ;;
        docker)
            [[ $output = *'index out of bounds'* ]]
            ;;
        *)
            false
            ;;
    esac

    # name is later
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=uhigtsbjmfps /etc/fstab /
FROM 00_tiny AS uhigtsbjmfps
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'does not exist'* ]]
            [[ $output != *'does not exist yet'* ]]  # so we review test
            ;;
        docker)
            [[ $output = *'pull access denied'*'repository does not exist'* ]]
            ;;
        *)
            false
            ;;
    esac

    # negative index
    run build_ -t tmpimg -f - . <<'EOF'
FROM 00_tiny
COPY --from=-1 /etc/fstab /
FROM 00_tiny
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    case $CH_TEST_BUILDER in
        ch-image)
            [[ $output = *'invalid negative stage index'* ]]
            ;;
        docker)
            [[ $output = *'index out of bounds'* ]]
            ;;
        *)
            false
            ;;
    esac
}


@test 'Dockerfile: FROM scratch' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # pull it; validate special handling
    run ch-image pull -v scratch
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'manifest: using internal library'* ]]
    [[ $output = *'no config found; initializing empty metadata'* ]]
    [[ $output != *'layer 1'* ]]  # no layers

    # remove
    ch-image delete scratch

    # build 1; validate pulled with special handling
    run ch-image build -v -t foo -f - . <<'EOF'
FROM scratch
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'base image not found, pulling'* ]]
    [[ $output = *'manifest: using internal library'* ]]
    [[ $output = *'no config found; initializing empty metadata'* ]]
    [[ $output != *'layer 1'* ]]  # no layers
    ls -lha "${CH_IMAGE_STORAGE}/img/foo/usr"
    [[ $(find /tmp/foo -mindepth 1 "${CH_IMAGE_STORAGE}/img/foo/usr") = '' ]]

    # build 2; validate not pulled
    run ch-image build -v -t tmpimg -f - . <<'EOF'
FROM scratch
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"base image found: ${CH_IMAGE_STORAGE}/img/scratch"* ]]
}
