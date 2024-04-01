load ../common

setup () {
    [[ $CH_TEST_BUILDER != none ]] || skip 'no builder'
}


@test 'Dockerfile: syntax quirks' {
    # These should all yield an output image, but we don’t actually care about
    # it, so re-use the same one.

    export CH_IMAGE_CACHE=disabled

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only' # FIXME: other builders?

    # No newline at end of file.
      printf 'FROM alpine:3.17\nRUN echo hello' \
    | ch-image build -t tmpimg -f - .

    # Newline before FROM.
    ch-image build -t tmpimg -f - . <<'EOF'

FROM alpine:3.17
RUN echo hello
EOF

    # Comment before FROM.
    ch-image build -t tmpimg -f - . <<'EOF'
# foo
FROM alpine:3.17
RUN echo hello
EOF

    # Single instruction.
    ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
EOF

    # Whitespace around comment hash.
    run ch-image -v build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
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
FROM alpine:3.17

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
  1. FROM alpine:3.17
copying image ...
  4. RUN.S true 
 13. RUN.S echo test1a
test1a
 16. RUN.S echo test1bc
test1bc
 21. RUN.S echo test2  a
test2 a
 24. RUN.S echo test2  b  c
test2 b c
 29. RUN.S echo test3a
test3a
 32. RUN.S echo test3bc
test3bc
 37. RUN.S echo test4   a
test4 a
 40. RUN.S echo test4   b   c
test4 b c
 45. RUN.S echo test5  a
test5 a
 48. RUN.S echo test5  b  c
test5 b c
 53. RUN.S echo test6  a
test6 a
 57. RUN.S echo test6    b
test6 b
 63. RUN.S echo test\ 7a
test 7a
 66. RUN.S echo test\ 7\ b
test 7 b
--force=seccomp: modified 0 RUN instructions
grown in 16 instructions: tmpimg
build slow? consider enabling the build cache
hint: https://hpc.github.io/charliecloud/command-usage.html#build-cache
warning: reprinting 1 warning(s)
warning: not yet supported, ignored: issue #777: .dockerignore file
EOF
)
    diff -u <(echo "$output_expected") <(echo "$output")
}


@test 'Dockerfile: syntax errors' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # Bad instruction. Also, -v should give interal blabber about the grammar.
    run ch-image -v build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
WEIRDAL
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # error message
    [[ $output = *"can"?"t parse: -:2,1"* ]]
    # internal blabber (varies by version)
    [[ $output = *'No terminal'*"'W'"*'at line 2 col 1'* ]]

    # Bad long option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --chown= foo bar
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can"?"t parse: -:2,14"* ]]

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
FROM alpine:3.17
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
FROM alpine:3.17
COPY --chown=foo --chown=bar fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'  2 COPY: repeated option --chown'* ]]

    # COPY invalid option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --foo=foo fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'COPY: invalid option --foo'* ]]

    # FROM invalid option.
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM --foo=bar alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'FROM: invalid option --foo'* ]]
}


@test 'Dockerfile: not-yet-supported features' {
    # This test also creates images we don’t care about.

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # FROM --platform
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM --platform=foo alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #778: FROM --platform'* ]]

    # other instructions
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
ADD foo
CMD foo
ENTRYPOINT foo
ONBUILD foo
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Ec 'not yet supported.+instruction') -eq 8 ]]
    [[ $output = *'warning: not yet supported, ignored: issue #782: ADD instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #780: CMD instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #780: ENTRYPOINT instruction'* ]]
    [[ $output = *'warning: not yet supported, ignored: issue #788: ONBUILD instruction'* ]]

    # .dockerignore files
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not yet supported, ignored: issue #777: .dockerignore file'* ]]

    # URL (Git repo) contexts
    run ch-image build -t not-yet-supported -f - \
        git@github.com:hpc/charliecloud.git <<'EOF'
FROM alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #773: URL context'* ]]
    run ch-image build -t tmpimg -f - \
        https://github.com/hpc/charliecloud.git <<'EOF'
FROM alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'error: not yet supported: issue #773: URL context'* ]]

    # variable expansion modifiers
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
ARG foo=README
COPY fixtures/${foo:+bar} .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'error: modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)'* ]]
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
ARG foo=README
COPY fixtures/${foo:-bar} .
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    # shellcheck disable=SC2016
    [[ $output = *'error: modifiers ${foo:+bar} and ${foo:-bar} not yet supported (issue #774)'* ]]
}


@test 'Dockerfile: unsupported features' {
    # This test also creates images we don’t care about.

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
FROM alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not supported, ignored: parser directives'* ]]
    [[ $(echo "$output" | grep -Fc 'parser directives') -eq 10 ]]

    # COPY --from
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --chown=foo fixtures/empty-file .
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'warning: not supported, ignored: COPY --chown'* ]]

    # Unsupported instructions
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
EXPOSE foo
HEALTHCHECK foo
MAINTAINER foo
STOPSIGNAL foo
USER foo
VOLUME foo
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $(echo "$output" | grep -Fc 'not supported') -eq 12 ]]
    [[ $output = *'warning: not supported, ignored: EXPOSE instruction'* ]]
    [[ $output = *'warning: not supported, ignored: HEALTHCHECK instruction'* ]]
    [[ $output = *'warning: not supported, ignored: MAINTAINER instruction'* ]]
    [[ $output = *'warning: not supported, ignored: STOPSIGNAL instruction'* ]]
    [[ $output = *'warning: not supported, ignored: USER instruction'* ]]
    [[ $output = *'warning: not supported, ignored: VOLUME instruction'* ]]
}


@test 'Dockerfile: ENV parsing' {
    scope standard

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
FROM almalinux_8ch

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
  env_actual=$(  echo "$output" \
               | sed -En "s/^(#[0-9]+ [0-9.]+ )?(\('chse_.+\))$/\2/p")
  echo "$env_actual"
  [[ $status -eq 0 ]]
  diff -u <(echo "$env_expected") <(echo "$env_actual")
}


@test 'Dockerfile: LABEL parsing' {

    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    label_expected=$(cat <<'EOF'
('chsl_0a', 'value 0a')
('chsl_0b', 'value 0b')
('chsl_2a', 'value2a')
('chsl_2b', 'value2b')
('chsl_3a', 'value3a')
('chsl_3b', 'value3b')
EOF
)
    run build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM almalinux_8ch

# Value has internal space.
LABEL chsl_0a value 0a
LABEL chsl_0b="value 0b"

# FIXME: See issue #1533. Quotes around keys are not removed in metadata.
#LABEL "chsl_1"="value 1"

# Multiple variables in the same instruction.
LABEL chsl_2a=value2a chsl_3a=value3a
LABEL chsl_2b=value2b \
    chsl_3b=value3b

# FIXME: currently a parse error.
#LABEL chsl_4=value4 chsl_5="value5 foo" chsl_6=value6\ foo chsl_7=\"value7\"

# FIXME: See issue #1512. Multiline values currently not supported.
#LABEL chsl_5 = "value\
#5"

# Print output with Python to avoid ambiguity.
RUN python3 -c 'import os; import json; labels = json.loads(open("/ch/metadata.json", "r").read())["labels"]; \
                [print((k,v)) for (k,v) in sorted(labels.items()) if "chsl_" in k]'
EOF
  echo "$output"
  [[ $status -eq 0 ]]
  diff -u <(echo "$label_expected") <(echo "$output" | grep -E "^\('chsl_")
}


@test 'Dockerfile: SHELL' {
   scope standard
   [[ $CH_TEST_BUILDER = buildah* ]] && skip "Buildah doesn't support SHELL"

   # test that SHELL command can change executables and parameters
   run build_ -t tmpimg --no-cache -f - . <<'EOF'
FROM alpine:3.17
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

   # test that it fails if shell doesn’t exist
   run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
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
FROM alpine:3.17
SHELL ["/bin/sh"]
RUN true
EOF
   echo "$output"
   [[ $status -ne 0 ]]  # different builders use different error exit codes
   [[ $output = *"/bin/sh: can't open 'true': No such file or directory"* ]]

   # test that it works with python3
   run build_ -t tmpimg -f - . <<'EOF'
FROM almalinux_8ch
SHELL ["/usr/bin/python3", "-c"]
RUN print ("hello")
EOF
   echo "$output"
   [[ $status -eq 0 ]]
   [[    $output = *"grown in 3 instructions: tmpimg"* \
      || $output = *"Successfully built"* \
      || $output = *"naming to"*"tmpimg done"* ]]
}


@test 'Dockerfile: ARG and ENV values' {
    # We use full scope for builders other than ch-image because (1) with
    # ch-image, we are responsible for --build-arg being implemented correctly
    # and (2) Docker and Buildah take a full minute for this test, vs. three
    # seconds for ch-image.
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        scope standard
    else
        scope full
    fi
    prerequisites_ok argenv

    sed_ () {
        # Print only lines listing a test variable, with instruction number
        # prefixes added by BuildKit stripped if present.
        sed -En "s/^(#[0-9]+ [0-9.]+ )?(chse_.+)$/\2/p"
    }

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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
        # environment. This is contrary to the “docker build” documentation;
        # “buildah bud” does not mention it either way. Tested on 18.09.7 and
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
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
        # Docker and Buildah don’t substitute provided values.
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
    env_actual=$(echo "$output" | sed_)
    echo "$env_actual"
    diff -u <(echo "$env_expected") <(echo "$env_actual")

    echo '*** ARG not in Dockerfile'
    # Note: We don’t test it, but for Buildah, the variable does show up in
    # the build environment.
    run build_ --build-arg chse_doesnotexist=foo \
               --no-cache -t tmpimg -f ./Dockerfile.argenv .
    echo "$output"
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $status -eq 1 ]]
        [[ $output = *'not consumed'* ]]
        [[ $output = *'chse_doesnotexist'* ]]
    else
        # Docker now (with BuildKit) just ignores the missing variable.
        [[ $status -eq 0 ]]
    fi

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


@test 'Dockerfile: ARG before FROM' {
    scope standard

    # single-stage
    run build_ --no-cache -t tmpimg - <<'EOF'
ARG os=alpine:3.17
ARG foo=bar
FROM $os
ARG baz=qux
RUN echo "os=$os foo=$foo baz=$baz"
RUN echo alpine=$(cat /etc/alpine-release | cut -d. -f1-2)
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ $CH_TEST_BUILDER != docker ]]; then  # Docker weird and inconsistent
        [[ $output = *'FROM alpine:3.17'* ]]
        [[ $output = *'os=alpine:3.17 foo=bar baz=qux'* ]]
    fi
    [[ $output = *'alpine=3.17'* ]]

    # multi-stage
    run build_ --no-cache -t tmpimg - <<'EOF'
ARG os1=alpine:3.16
ARG os2=alpine:3.17
FROM $os1
RUN echo "1: os1=$os1 os2=$os2"
RUN echo alpine1=$(cat /etc/alpine-release | cut -d. -f1-2)
FROM $os2
RUN echo "2: os1=$os1 os2=$os2"
RUN echo alpine2=$(cat /etc/alpine-release | cut -d. -f1-2)
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ $CH_TEST_BUILDER != docker ]]; then
        [[ $output = *'FROM alpine:3.16'* ]]
        [[ $output = *'FROM alpine:3.17'* ]]
        [[ $output = *'1: os1=alpine:3.16 os2=alpine:3.17'* ]]
        [[ $output = *'2: os1=alpine:3.16 os2=alpine:3.17'* ]]
        [[ $output = *'alpine1=3.16'* ]]
        [[ $output = *'alpine2=3.17'* ]]
    fi

    # no default value
    run build_ --no-cache -t tmpimg - <<'EOF'
ARG os
FROM $os
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        # shellcheck disable=SC2016
        [[ $output = *'base name ($os) should not be blank'* ]]
    else
        # shellcheck disable=SC2016
        [[ ${lines[-2]} = 'error: image reference contains an undefined variable: $os' ]]
    fi

    # set with --build-arg
    run build_ --no-cache --build-arg=os=alpine:3.17 -t tmpimg - <<'EOF'
ARG os=alpine:3.17
FROM $os
RUN echo "os=$os"
RUN echo alpine=$(cat /etc/alpine-release | cut -d. -f1-2)
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ $CH_TEST_BUILDER != docker ]]; then
        [[ $output = *'FROM alpine:3.17'* ]]
        [[ $output = *'os=alpine:3.17'* ]]
    fi
    [[ $output = *'alpine=3.17'* ]]

    # both before and after FROM
    run build_ --no-cache -t tmpimg - <<'EOF'
ARG foo=bar
FROM alpine:3.17
ARG foo=baz
RUN echo "foo=$foo"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'foo=baz'* ]]  # second wins
}


@test 'Dockerfile: FROM multistage alias' {
    scope standard
    # Ensure multisage alias works and reports correct base with ARG.
    run build_ --no-cache -t tmpimg -f - . <<'EOF'
ARG BASEIMG=alpine:3.17
FROM $BASEIMG as a
RUN true
FROM a as b
RUN true
FROM b
RUN true
EOF
    # We only care that other builders return 0; we only check ch-image output.
    echo "$output"
    [[ $status -eq 0 ]]
    # There is a distinction between the image tag, displayed base/alias text,
    # and internal storage tag (e.g., _stage%s suffix). Exercise the following.
    #
    #  1. checkout base image ARG, as stage_0 with alias 'a', and display
    #     correct base text;
    #
    #  2. checkout stage_0 as stage_1, with alias 'b', and display correct base
    #     text (alias 'a', not ARG);
    #
    #  3. checkout stage_1 as image tag and display correct base text, (alias
    #     'b', not 'a' or ARG).
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *"ARG BASEIMG='alpine:3.17'"* ]]
        [[ $output = *'FROM alpine:3.17 AS a'* ]]
        [[ $output = *'RUN.S true'* ]]
        [[ $output = *'FROM a AS b'* ]]
        [[ $output = *'RUN.S true'* ]]
        [[ $output = *'FROM b'* ]]
        [[ $output = *'RUN.S true'* ]]
        run ch-image list
        echo "$output"
        [[ $status -eq 0 ]]
        [[ $output = *'alpine:3.17'* ]]
        [[ $output = *'tmpimg'* ]]
        [[ $output = *'tmpimg_stage0'* ]]
        [[ $output = *'tmpimg_stage1'* ]]
    fi
}


@test 'Dockerfile: FROM --arg' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # --arg present but not used in image name
    run ch-image build --no-cache -t tmpimg -f - . <<'EOF'
FROM --arg=foo=bar alpine:3.17
RUN echo "1: foo=$foo"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'FROM --arg=foo=bar alpine:3.17'* ]]
    [[ $output = *'1: foo=bar'* ]]

    # --arg used in image name
    run ch-image build --no-cache -t tmpimg -f - . <<'EOF'
FROM --arg=os=alpine:3.17 $os
RUN echo "1: os=$os"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'FROM --arg=os=alpine:3.17 alpine:3.17'* ]]
    [[ $output = *'1: os=alpine:3.17'* ]]

    # multiple --arg
    run ch-image build --no-cache -t tmpimg -f - . <<'EOF'
FROM --arg=foo=bar --arg=os=alpine:3.17 $os
RUN echo "1: foo=$foo os=$os"
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'FROM --arg=foo=bar --arg=os=alpine:3.17 alpine:3.17'* ]]
    [[ $output = *'1: foo=bar os=alpine:3.17'* ]]
}

@test 'Dockerfile: COPY list form' {
    scope standard
    [[ $CH_TEST_BUILDER == ch-image ]] || skip 'ch-image only'

    # single source
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY ["fixtures/empty-file", "."]
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"COPY ['fixtures/empty-file'] -> '.'"* ]]
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/empty-file

    # multiple source
    run ch-image build -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY ["fixtures/empty-file", "fixtures/README", "."]
EOF
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *"COPY ['fixtures/empty-file', 'fixtures/README'] -> '.'"* ]]
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/empty-file
    test -f "$CH_IMAGE_STORAGE"/img/tmpimg/README
}

@test 'Dockerfile: COPY to nonexistent directory' {
    scope standard

    # file to one directory that doesn’t exist
    build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
RUN ! test -e /foo
COPY fixtures/empty-file /foo/file_
RUN test -f /foo/file_
EOF

    # file to multiple directories that don’t exist
    build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
RUN ! test -e /foo
COPY fixtures/empty-file /foo/bar/file_
RUN test -f /foo/bar/file_
EOF

    # directory to one directory that doesn’t exist
    build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
RUN ! test -e /foo
COPY fixtures /foo/dir_
RUN test -d /foo/dir_ && test -f /foo/dir_/empty-file
EOF

    # directory: multiple parents DNE
    build_ --no-cache -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
RUN ! test -e /foo
COPY fixtures /foo/bar/dir_
RUN test -d /foo/bar/dir_ && test -f /foo/bar/dir_/empty-file
EOF
}

@test 'Dockerfile: COPY errors' {
    scope standard
    [[ $CH_TEST_BUILDER = buildah* ]] && skip 'Buildah untested'

    # Dockerfile on stdin, so no context directory.
    run build_ -t tmpimg - <<'EOF'
FROM alpine:3.17
COPY doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        # This error message seems wrong. I was expecting something about
        # no context, so COPY not allowed.
        [[    $output = *'file does not exist'* \
           || $output = *'not found'* ]]
    else
        [[ $output = *'no context'* ]]
    fi

    # SRC not inside context directory.
    #
    # Case 1: leading “..”.
    run build_ -t tmpimg -f - sotest <<'EOF'
FROM alpine:3.17
COPY ../common.bash .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'outside'*'context'* \
       || $output = *'not found'* ]]
    # Case 2: “..” inside path.
    run build_ -t tmpimg -f - sotest <<'EOF'
FROM alpine:3.17
COPY lib/../../common.bash .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'outside'*'context'* \
       || $output = *'not found'* ]]
    # Case 3: symlink leading outside context directory.
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY fixtures/symlink-to-tmp .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = docker ]]; then
        [[    $output = *'file does not exist'* \
           || $output = *'not found'* ]]
    else
        [[ $output = *'outside'*'context'* ]]
    fi

    # Multiple sources and non-directory destination.
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY Build.missing common.bash /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    # OK so with Docker now that BuildKit is the default (v24.0.5), this build
    # *succeeds* and /etc/fstab is overwritten with the contents of
    # common.bash (and Build.missing is ignored AFAICT). 👎
    if [[ $CH_TEST_BUILDER != docker ]]; then
        run build_ -t foo -f - . <<'EOF'
FROM alpine:3.17
COPY Build.missing common.bash /etc/fstab
EOF
        echo "$output"
        [[ $status -ne 0 ]]
        [[ $output = *'not a directory'* ]]
    fi
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY run /etc/fstab/
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not a directory'* ]]
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY run /etc/fstab
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'not a directory'* \
       || $output = *'cannot copy to non-directory'* ]]

    # No sources given.
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *"error: can"?"t parse: -:2,7"* ]]
    else
        [[ $output = *'COPY requires at least two arguments'* ]]
    fi
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY ["."]
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    if [[ $CH_TEST_BUILDER = ch-image ]]; then
        [[ $output = *'error: source or destination missing'* ]]
    else
        [[ $output = *'COPY requires at least two arguments'* ]]
    fi

    # No sources found.
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not found'* ]]

    # Some sources found.
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY fixtures/README doesnotexist .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[ $output = *'not found'* ]]

    # No context with Dockerfile on stdin by context “-”
    run build_ -t tmpimg - <<'EOF'
FROM alpine:3.17
COPY fixtures/README .
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'error: no context because '?'-'?' given'* \
       || $output = *'COPY failed: file not found in build context or'* \
       || $output = *'no such file or directory'* ]]
}


@test 'Dockerfile: COPY --from errors' {
    scope standard
    [[ $CH_TEST_BUILDER = buildah* ]] && skip 'Buildah untested'

    # Note: Docker treats several types of erroneous --from names as another
    # image and tries to pull it. To avoid clashes with real, pullable images,
    # we use the random name “uhigtsbjmfps” (https://www.random.org/strings/).

    # current index
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=0 /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'current'*'stage'* \
       || $output = *'circular dependency'* ]]

    # current name
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17 AS uhigtsbjmfps
COPY --from=uhigtsbjmfps /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'current stage'* \
       || $output = *'access denied'*'repository does not exist'* \
       || $output = *'circular dependency'* ]]

    # index does not exist
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=1 /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'does not exist'* \
       || $output = *'index out of bounds'* \
       || $output = *'invalid stage index'* ]]

    # name does not exist
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=uhigtsbjmfps /etc/fstab /
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'does not exist'* \
       || $output = *'pull access denied'*'repository does not exist'* ]]

    # index exists, but is later
    if [[ $CH_TEST_BUILDER != docker ]]; then  # BuildKit can work out of order
        run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=1 /etc/fstab /
FROM alpine:3.17
EOF
        echo "$output"
        [[ $status -ne 0 ]]
        [[ $output = *'does not exist yet'* ]]
    fi

    # name is later
    if [[ $CH_TEST_BUILDER != docker ]]; then  # BuildKit can work out of order
        run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=uhigtsbjmfps /etc/fstab /
FROM alpine:3.17 AS uhigtsbjmfps
EOF
        echo "$output"
        [[ $status -ne 0 ]]
        [[ $output = *'does not exist'* ]]
        [[ $output != *'does not exist yet'* ]]  # so we review test
    fi

    # negative index
    run build_ -t tmpimg -f - . <<'EOF'
FROM alpine:3.17
COPY --from=-1 /etc/fstab /
FROM alpine:3.17
EOF
    echo "$output"
    [[ $status -ne 0 ]]
    [[    $output = *'invalid negative stage index'* \
       || $output = *'index out of bounds'* \
       || $output = *'invalid stage index'* ]]
}


@test 'Dockerfile: COPY from previous stage, no context' {
    # Normally, COPY is disallowed if there’s no context directory, but if
    # it’s from a previous stage, it should work. See issue #1381.

    scope standard
    [[ $CH_TEST_BUILDER == ch-image ]] || skip 'ch-image only'

    run ch-image build --no-cache -t foo - <<'EOF'
FROM alpine:3.16
FROM alpine:3.17
COPY --from=0 /etc/os-release /
EOF
    echo "$output"
    [[ "$status" -eq 0 ]]
}


@test 'Dockerfile: FROM scratch' {
    scope standard
    [[ $CH_TEST_BUILDER = ch-image ]] || skip 'ch-image only'

    # remove if it exists
    ch-image delete scratch || true

    # pull and validate special handling
    run ch-image pull -v scratch
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'manifest: using internal library'* ]]
    [[ $output != *'layer 1'* ]]  # no layers
}


@test 'Dockerfile: bad image reference' {
    scope standard
    [[ $CH_TEST_BUILDER == ch-image ]] || skip 'ch-image only'

    run ch-image build -t tmpimg - <<'EOF'
FROM /alpine:3.17
EOF
    echo "$output"
    [[ $status -eq 1 ]]
    [[ ${lines[-3]} = 'error: image ref syntax, char 1: /alpine:3.17' ]]
}
