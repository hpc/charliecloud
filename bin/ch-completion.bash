#!/bin/bash

# Completion script for Charliecloud
#
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
#   * Call-by-reference for bash function args:
#     https://unix.stackexchange.com/a/224564
#
#
# SYNTAX GLOSSARY
#
# FIXME: Add syntax glossary
#

# FIXME: disable shellcheck SC2034 for this? (See base.sh)
CH_BIN="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Debugging log
if [[ -f "/tmp/ch-completion.log" ]]; then
    rm /tmp/ch-completion.log
fi

## ch-image ##

# Subcommands and options for ch-image
#
__image_subcommands="build build-cache delete gestalt
                     import list pull push reset undelete"

__image_build_opts="-b --bind --build-arg -f --file --force
                    --force-cmd -n --dry-run --parse-only -t --tag"

__image_common_opts="-a --arch --always-download --auth --cache 
                     --cache-large --dependencies -h --help 
                     --no-cache --no-lock --profile --rebuild 
                     --password-many -s --storage --tls-no-verify 
                     -v --verbose --version"

## ch-image ##

# Completion function for ch-image
#
__ch-image_completion () {
    local prev
    local cur
    local words
    local sub_cmd
    local extras=""
    _get_comp_words_by_ref -n : cur prev words

    # If "$cur" is non-empty, we want to ignore it as a potential subcommand
    # to avoid unwanted behavior. “${words[@]::${#words[@]}-1}” gives you all
    # but the last element of the array “words,” so if "$cur" is non-empty,
    # pass it to __ch_subcommand_get. Otherwise pass all elements of “words.”
    if [[ -n "$cur" ]]; then
        sub_cmd=$(__ch_subcommand_get "$__image_subcommands" "${words[@]::${#words[@]}-1}")
    else
        sub_cmd=$(__ch_subcommand_get "$__image_subcommands" "${words[@]}")
    fi
    echo "sub command: $sub_cmd" >> /tmp/ch-completion.log

    # Common opts that take args
    #
    case "$prev" in
    -a | --arch )
        # FIXME: Add commonly available architectures?
        COMPREPLY=( $(compgen -W "host yolo" -- $cur) )
        return 0
        ;;
    --cache-large )
        # This is just a user-specified number. Can't autocomplete
        COMPREPLY=()
        return 0
        ;;
    -s | --storage )
        compopt -o nospace
        COMPREPLY=( $(compgen -d -S / -- $cur) )
        return 0
        ;;
    esac

    case "$sub_cmd" in
    build )
        # FIXME: opts with args that I need to revisit for this logic
        #
        #   * --build-arg KEY[=VALUE]
        #   * --force-cmd=CMD,ARG1[,ARG2...]
        #
        case "$prev" in
        # Go through a list of potential subcommand-specific opts to see if
        # “$cur” should be an argument. Otherwise, default to CONTEXT or any
        # valid option (common or subcommand-specific).
        -f|--file )
            compopt -o nospace
            COMPREPLY=( $(__compgen_filepaths "$cur") )
            return 0
            ;;
        -t )
            # We can't autocomplete a tag, so we're not even gonna allow
            # autocomplete after this option.
            COMPREPLY=()
            return 0
            ;;
        *)
            # Autocomplete to context directory, common opt, or build-specific opt
            echo "compgen bit:" >> /tmp/ch-completion.log
            # --force can take “fakeroot” or “seccomp” as an argument, or no
            # argument at all. To account for this, we add those two arguments
            # to the list of compgen suggestions, which allows compgen to autocomplete
            # to “fakeroot,” “seccomp,” or anything that could logically follow
            # “--force” with no argument.
            if [[ "$prev" == "--force" ]]; then
                extras="$extras fakeroot seccomp"
            fi
            COMPREPLY=( $(compgen -W "$__image_build_opts $extras"  -- $cur) )
            # Completion for the context directory. Note that we put this under an
            # “if” statement so that the “nospace” option isn't applied to all
            # completions that come after the “build” subcommand, as that would be
            # inconvenient.
            if [[ -n "$(compgen -d -S / -- $cur)" ]]; then
                compopt -o nospace
                COMPREPLY+=( $(compgen -d -S / -- $cur) )
            fi
            ;;
        esac
        ;;
    build-cache )
        COMPREPLY=( $(compgen -W "--reset --gc --tree --dot" -- $cur) )
        ;;
    delete | list)
        # FIXME: Is it janky to include “list” here? I'm leaning towards
        #        “not that janky,” others may disagree.
        if [[ "$sub_cmd" == "list" ]]; then
            extras="$extras -l --long"
        fi
        # FIXME: This call to “ch-image list” likely won't work if the user
        #        has specified a non-standard storage directory. Likely need
        #        to make a parser for that.
        COMPREPLY=( $(compgen -W "$($CH_BIN/ch-image list) $extras" -- $cur) )
        __ltrim_colon_completions "$cur"
        ;;
    gestalt )
        COMPREPLY=( $(compgen -W "bucache bucache-dot python-path 
                                  storage-path" -- $cur) )
        ;;
    import )
        # FIXME: Unimplemented
        COMPREPLY=()
        ;;
    push )
        # FIXME: Unimplemented
        COMPREPLY=()
        ;;
    '' )
        # Only autocomplete subcommands if there's no subcommand present.
        COMPREPLY=( $(compgen -W "$__image_subcommands" -- $cur) )
        ;;
    esac

    # If we've made it this far, the last remaining option for completion
    # is common opts. Note that we do the “-n” check to avoid being overzealous
    # with our suggestions.
    if [[ -n "$cur" ]]; then
        COMPREPLY+=( $(compgen -W "$__image_common_opts" -- $cur) )
        return 0
    fi
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

complete -F __ch-image_completion ch-image