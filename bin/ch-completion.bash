#!/bin/bash

# Completion script for Charliecloud
#
# Resources for understanding this script:
#
#   * Bash parameter expansion:
#     https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
#
#   * Bash completion builtins (compgen, comopt, etc.):
#     https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion-Builtins.html
#
#   * Bash completion variables (e.g. COMPREPLY):
#     https://devmanual.gentoo.org/tasks-reference/completion/index.html
#
#
# SYNTAX GLOSSARY
#
# 

# might need to disable shellcheck SC2034 for this (see base.sh)
CH_BIN="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "/tmp/ch-completion.log" ]]; then
    rm /tmp/ch-completion.log
fi

## ch-image ##

# Subcommands for ch-image and their options
#
# FIXME: Figure out whether or not opts should be assigned to different
#        lists based on whether or not they accept/require args.
#
__image_subcommands="build build-cache delete gestalt
                     import list pull push reset undelete"

#__image_build_opts="-b --bind --build-arg -f --file --force
#                    --force-cmd -n --dry-run --parse-only -t --tag"

__image_build_opts_noarg="-n --dry-run --parse-only"

__image_build_opts_arg="-b --bind --build-arg -f --file --force --force-cmd
                        -t --tag"

__image_build_opts="$__image_build_opts_noarg $__image_build_opts_arg"

__image_common_opts_noarg="--always-download --auth --cache --no-cache
                           --no-lock --profile --rebuild --password-many
                           --tls-no-verify -v --verbose"

__image_common_opts_arg="-a --arch --cache-large -s --storage-dir"

__image_common_opts="$__image_common_opts_arg $__image_common_opts_noarg"

# Autocompletion function for ch-image
#
__ch-image_completion () {
    local prev
    local cur
    local words
    local sub_cmd
    local extras=""
    _get_comp_words_by_ref -n : cur prev words

    #echo "all but last: ${words[@]::${#words[@]}-1}" >> /tmp/ch-completion.log
    #
    # If "$cur" is non-empty, we want to ignore it as a potential subcommand
    # to avoid unwanted behavior. To do this, we pass __ch_subcommand_get
    # the command line minus the last word if "$cur" is non-empty, and the
    # full command line otherwise.
    if [[ -n "$cur" ]]; then
        sub_cmd=$(__ch_subcommand_get "$__image_subcommands" "${words[@]::${#words[@]}-1}")
    else
        sub_cmd=$(__ch_subcommand_get "$__image_subcommands" "${words[@]}")
    fi
    #local sub_cmd=$(__ch_subcommand_get "$__image_subcommands" "${words[@]}")
    echo "sub command: $sub_cmd" >> /tmp/ch-completion.log

    case "$sub_cmd" in
    build )
        # FIXME: opts with args that I need to revisit for this logic
        #
        #   * --build-arg KEY[=VALUE]
        #   * --force-cmd=CMD,ARG1[,ARG2...]
        #
        echo "  \$prev: $prev" >> /tmp/ch-completion.log
        case "$prev" in
        # Go through a list of potential subcommand-specific opts to see if
        # “$cur” should be an argument. Otherwise, default to CONTEXT or a
        # non-argument-accepting opt. (FIXME: revise this comment)
        -f|--file )
            compopt -o nospace
            COMPREPLY=( $(__compgen_filepaths "$cur") )
            ;;
        -t )
            # We can't autocomplete a tag, so we're not even gonna allow
            # autocomplete after this option.
            COMPREPLY=()
            ;;
        *)
            # Autocomplete to context directory, common opt, or noarg opt
            #
            # FIXME: Need to add switch statement that goes through list of
            #        common opts that accept args.
            #
            # FIXME: “compopt -o nospace” means spaces don't get appended to
            #        “$cur” for this “compgen” call. This is useful when you're
            #        trying to specify the context directory, not so useful if
            #        you want an option instead. Look into alternative?
            #        Resources that might be of interest: 
            #           https://stackoverflow.com/a/40227233
            #           https://stackoverflow.com/questions/2339246/add-spaces-to-the-end-of-some-bash-autocomplete-options-but-not-to-others
            #           https://stackoverflow.com/questions/26509260/bash-tab-completion-with-spaces
            #
            echo "compgen bit:" >> /tmp/ch-completion.log
            # --force can take “fakeroot” or “seccomp” as an argument, or
            # no argument at all, in which case it defaults to seccomp. To
            # account for this, we simply add those two arguments to the
            # list of compgen suggestions, which allows compgen to autocomplete
            # to “fakeroot,” “seccomp,” or anything that could logically follow
            # “--force” with no argument.
            if [[ "$prev" == "--force" ]]; then
                extras="$extras fakeroot seccomp"
            fi
            #foo=$(compgen -d -S / -- $cur)
            #echo $(compgen -d -S / -- $cur) >> /tmp/ch-completion.log
            compopt -o nospace
            #COMPREPLY=( $(compgen -W "$__image_build_opts $__image_common_opts $foo $extras"  -- $cur) )
            COMPREPLY=( $(compgen -W "$__image_build_opts $__image_common_opts $(compgen -d -S / -- $cur) $extras"  -- $cur) )
            ;;
        esac
        ;;
    delete )
        # FIXME: use filepath for ch-image or assume it's in PATH?
        COMPREPLY=( $(compgen -W "$($CH_BIN/ch-image list)" -- $cur) )
        __ltrim_colon_completions "$cur"
        return 0
        ;;
    '' )
        # Only autocomplete subcommands if there's no subcommand present.
        COMPREPLY=( $(compgen -W "$__image_subcommands" -- $cur) )
        return 0
        ;;
    esac
}

## Helper functions ##

# Kludge up a way to look through array of words and determine the 
# subcommand. Note that the double for loop doesn't take that much
# time, since the Charliecloud command line is relatively short.
#
# Usage:
#   __ch_subcommand_get [subcommands] [words]
#
# Example:
#   >> __ch_subcommand_get "build build-cache ... undelete" \
#                          "ch-image --foo build ..."
#      build
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
    echo "$subcmd"
}

# Code that I shamelessly stole from StackOverflow 
#   (https://stackoverflow.com/a/40227233)
# Returns filenames and directories, appending a slash to directory names.
__compgen_filepaths() {
    local cur="$1"

    # Files, excluding directories, with no trailing slashes. The
    # grep performs an inverted substring match on the list of
    # directories and the list of files respectively produced by 
    # compgen. The compgen statements also prepend (-P) a “^” and
    # append (-S) a “$” to the file/dir names to avoid the case
    # where a substring matching a dirname is erroniously removed
    # from a filename by the inverted match. These delimiters are
    # then removed by the “sed”. (See the StackOverflow post cited
    # above for OP’s explanation of this code).
    grep -v -F -f <(compgen -d -P ^ -S '$' -- "$cur") \
        <(compgen -f -P ^ -S '$' -- "$cur") |
        sed -e 's/^\^//' -e 's/\$$/ /'
    
    # Directories with trailing slashes:
    compgen -d -S / -- "$cur"
}

#complete -o default -F __ch-image_completion ch-image
complete -F __ch-image_completion ch-image