#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

## ch-image ##

# Subcommands for ch-image
#
__image_subcommands="build build-cache delete gestalt
                     import list pull push reset undelete"

__image_build_opts="-b --bing --build-arg -f --file --force
                    --force-cmd -n --dry-run --parse-only -t --tag"

__image_common_opts_noarg="--always-download --auth --cache --no-cache
                           --no-lock --profile --rebuild --password-many
                           --tls-no-verify -v --verbose"

__image_common_opts_arg="-a --arch --cache-large -s --storage-dir"

# Autocompletion function for ch-image
#
__ch-image_completion () {
    local prev
    local cur
    local words
    _get_comp_words_by_ref -n : cur prev words

    local sub_command=$(__ch_subcommand_get "$__image_subcommands" "${words[@]}")

    case "$prev" in
    delete )
        # FIXME: use filepath for ch-image or assume it's in PATH?
        COMPREPLY=( $(compgen -W "$($SCRIPT_DIR/ch-image list)" -- $cur) )
        __ltrim_colon_completions "$cur"
        return 0
        ;;
    *ch-image )
        COMPREPLY=( $(compgen -W "$__image_subcommands" -- $cur) )
        return 0
        ;;
    esac
}

## Helper functions ##

# Kludge up a way to look through array of words and determine the 
# subcommand. Note that the double for loop doesn't take that much
# time, since the charliecloud command line is relatively short.
#
# Usage:
#   __ch_subcommand_get [subcommands] [words]
#
__ch_subcommand_get () {
    local cmd subcmd
    local cmds="$1"
    shift 1
    for word in "$@"
    do
        for cmd in $cmds
        do
            if [[ "$word" == "$cmd" ]]; then
                subcmd="$cmd"
            fi
        done
    done
    echo "sub command: $subcmd" >> /tmp/ch-complete-sub_cmd.log
    echo "$subcmd"
}

complete -F __ch-image_completion ch-image