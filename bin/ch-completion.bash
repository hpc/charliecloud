#!/bin/bash

# Completion script for Charliecloud
#
#
# Resources for understanding this script:
#
#   * Everything bash:
#     https://www.gnu.org/software/bash/manual/html_node/index.html
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
## SYNTAX GLOSSARY ##
#
# Source:
# https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
#
# ${array[i]}
#   Gives the ith element of “array”. Note that bash arrays are indexed
#   at zero, as all things should be.
#
# ${array[@]}
#   Expands “array” to its member elements.
#
# ${#parameter}
#   Gives the length of “parameter.” If “parameter” is a string, this
#   expansion gives you the character length of the string. If “paramter”
#   is an array subscripted by “@” or “*” (e.g. “foo[@]”), then the
#   expansion gives you the number of elements in the array.
#
# ${parameter:offset:length}
#   A.k.a. substring expansion. If “parameter” is a string, expand up to
#   “length” characters, starting with the character at position “offset.”
#   If “offset” is unspecified, start at the first character. If “parameter”
#   is an array subscripted by “@” or “*,” (e.g. “foo[@]”) expand up to
#   “length” elements, starting at the element at position “offset” (e.g.
#   “${foo[offset]}”).
#
#   Example 1 (string):
#   $ foo="foo_bar_baz"
#   $ echo ${foo::7}
#   foo_bar
#   $ echo ${foo:1:7}
#   oo_bar_
#
#   Example 2 (array):
#   $ foo=("foo" "bar" "baz" "qux")
#   $ echo ${foo[@]::3}
#   foo bar baz
#   $ echo ${foo[@]:1:3}
#   bar baz qux
#
# FIXME: Add syntax glossary
#

# Possible extensions once this is merged:
#   * Add completion support for non-bash shells (e.g. zsh and tchs).
#     see https://github.com/git/git/tree/master/contrib/completion
#   * Add support for mid-line completion (possibly using COMP_POINT,
#     see https://devmanual.gentoo.org/tasks-reference/completion/index.html).
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
_image_subcommands="build build-cache delete gestalt
                    import list pull push reset undelete"

_image_build_opts="-b --bind --build-arg -f --file --force
                   --force-cmd -n --dry-run --parse-only -t --tag"

_image_common_opts="-a --arch --always-download --auth --cache
                    --cache-large --dependencies -h --help
                    --no-cache --no-lock --profile --rebuild
                    --password-many -s --storage --tls-no-verify
                    -v --verbose --version"

## ch-image ##

# Completion function for ch-image
#
_ch_image_completion () {
    local prev
    local cur
    local words
    local sub_cmd
    local strg_dir
    local extras=""
    _get_comp_words_by_ref -n : cur prev words

    # If "$cur" is non-empty, we want to ignore it as a potential subcommand
    # to avoid unwanted behavior. “${words[@]::${#words[@]}-1}” gives you all
    # but the last element of the array “words” (see syntax glossary above) so 
    # if "$cur" is non-empty, pass it to _ch_subcommand_get. Otherwise pass all
    # elements of “words.”
    if [[ -n "$cur" ]]; then
        sub_cmd=$(_ch_subcommand_get "$_image_subcommands" "${words[@]::${#words[@]}-1}")
        strg_dir=$(_ch_find_storage "${words[@]::${#words[@]}-1}")
    else
        sub_cmd=$(_ch_subcommand_get "$_image_subcommands" "${words[@]}")
        strg_dir=$(_ch_find_storage "${words[@]}")
    fi
    echo "sub command: $sub_cmd" >> /tmp/ch-completion.log
    echo "storage dir: $strg_dir" >> /tmp/ch-completion.log
    echo "len storage dir: ${#strg_dir}" >> /tmp/ch-completion.log

    # Common opts that take args
    #
    case "$prev" in
    -a | --arch )
        # FIXME: Remove yolo?
        # FIXME: Missing common architectures?
        COMPREPLY=( $(compgen -W "host yolo 386 amd64 arm/v6 
                                  arm/v7 arm64/v8 ppc64le s390x" -- $cur) )
        return 0
        ;;
    --cache-large )
        # This is just a user-specified number. Can't autocomplete
        COMPREPLY=()
        return 0
        ;;
    -s | --storage )
        # This “if” helps avoid overzealous completion. E.g. if there's
        # only one subdir of the current dir, this command completes to
        # that dir even if "$cur" is empty. I didn't like that, hence the
        # “if”.
        if [[ -n "$cur" ]]; then
            compopt -o nospace
            COMPREPLY=( $(compgen -d -S / -- $cur) )
        fi
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
            COMPREPLY=( $(_compgen_filepaths "$cur") )
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
            COMPREPLY=( $(compgen -W "$_image_build_opts $extras"  -- $cur) )
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
        # The following check seems to fix a bug where the completion
        # function initialzes an empty storage directory.
        if [[ -n "$(ls $strg_dir/img)" ]]; then
            COMPREPLY=( $(compgen -W "$($CH_BIN/ch-image list -s $strg_dir) $extras" -- $cur) )
            __ltrim_colon_completions "$cur"
        fi
        ;;
    gestalt )
        COMPREPLY=( $(compgen -W "bucache bucache-dot python-path
                                  storage-path" -- $cur) )
        ;;
    import )
        # Complete dirs and files matching the globs “*.tar.*” and “*.tgz”
        # (a.k.a. tarballs).
        COMPREPLY+=( $(_compgen_filepaths -X "!*.tar.* !*tgz" "$cur") )
        if [[ ${#COMPREPLY} -gt 0 ]]; then
            compopt -o nospace
        fi
        ;;
    push )
        if [[ "$prev" == "--image" ]]; then
            compopt -o nospace
            COMPREPLY=( $(compgen -d -S / -- $cur) )
            return 0
        # The following check seems to fix a bug where the completion
        # function initialzes an empty storage directory.
        elif [[ -n "$(ls "$strg_dir"/img)" ]]; then
            COMPREPLY=( $(compgen -W "$($CH_BIN/ch-image list -s $strg_dir) --image" -- "$cur") )
            _ltrim_colon_completions "$cur"
        fi
        ;;
    undelete )
        # FIXME: Update with “ch-image undelete --list” once #1551 drops
        COMPREPLY=()
        ;;
    '' )
        # Only autocomplete subcommands if there's no subcommand present.
        COMPREPLY=( $(compgen -W "$_image_subcommands" -- $cur) )
        ;;
    esac

    # If we've made it this far, the last remaining option for completion
    # is common opts. Note that we do the “-n” check to avoid being overzealous
    # with our suggestions.
    if [[ -n "$cur" ]]; then
        COMPREPLY+=( $(compgen -W "$_image_common_opts" -- $cur) )
        return 0
    fi
}

## Helper functions ##

# Figure out which storage directory to use (including cli-specified
# storage).
# FIXME: Can probably cook up a sed pattern that'll remove the need
#        for the “if” statement.
_ch_find_storage () {
    if [[ -n "$(grep -Eo "(\-\-storage|[^\-]\-s)" <<< "$@")" ]]; then
        sed -e 's/\(.*\)\(--storage\|[^-]-s\)\ *\([^ ]*\)\(.*$\)/\3/g' <<< "$@"
    elif [[ -n "$CH_IMAGE_STORAGE" ]]; then
        echo "$CH_IMAGE_STORAGE"
    else
        echo "/var/tmp/$USER.ch/"
    fi
}

# Kludge up a way to look through array of words and determine the
# subcommand. Note that the double for loop doesn't take that much
# time, since the Charliecloud command line is relatively short.
#
# Usage:
#   _ch_subcommand_get [subcommands] [words]
#
# Example:
#   >> _ch_subcommand_get "build build-cache ... undelete" \
#                         "ch-image --foo build ..."
#      build
_ch_subcommand_get () {
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
# This function takes option “-X,” a string of space-separated glob patterns
# to be excluded from file completion using the compgen option of the same
# name (see https://devdocs.io/bash/programmable-completion-builtins#index-compgen)
_compgen_filepaths() {
    local filterpats=("")
    if [[ "$1" == "-X" && 1 < ${#@} ]]; then
        # Read a string into an array:
        #   https://stackoverflow.com/a/10586169
        # Pitfalls:
        #   https://stackoverflow.com/a/45201229
        # FIXME: Need to modify $IFS before doing this?
        read -ra filterpats <<< "$2"
        shift 2
    fi

    local cur="$1"

    # Files, excluding directories, with no trailing slashes. The
    # grep performs an inverted substring match on the list of
    # directories and the list of files respectively produced by
    # compgen. The compgen statements also prepend (-P) a “^” and
    # append (-S) a “$” to the file/dir names to avoid the case
    # where a substring matching a dirname is erroniously removed
    # from a filename by the inverted match. These delimiters are
    # then removed by the “sed”. (See the StackOverflow post cited
    # above for OP’s explanation of this code). The for loop iterates
    # through exclusion patterns specified by the “-X” option. If
    # “-X” isn't specified, the code in the loop executes once,
    # with no patterns excluded (“-X ""”).
    for pat in "${filterpats[@]}"
    do
        grep -v -F -f <(compgen -d -P ^ -S '$' -X "$pat" -- "$cur") \
            <(compgen -f -P ^ -S '$' -X "$pat" -- "$cur") |
            sed -e 's/^\^//' -e 's/\$$/ /'
    done

    # Directories with trailing slashes:
    compgen -d -S / -- "$cur"
}

complete -F _ch_image_completion ch-image