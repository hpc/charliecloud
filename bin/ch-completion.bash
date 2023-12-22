# Completion script for Charliecloud

# This ShellCheck error pops up whenever we do “COMPREPLY=( $(compgen [...]) )”.
# This seems to be standard for implementations of bash completion, and we didn't
# like the suggested alternatives, so we disable it here.
# shellcheck disable=SC2207

# SC2034 complains about modifying variables by reference in
# _ch_run_image_finder. Disable it.
# shellcheck disable=SC2034

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


## SYNTAX GLOSSARY ##
#
# This script uses syntax that may be confusing for bash newbies and those who
# are rusty.
#
# Source:
# https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
#
# ${array[i]}
#   Gives the ith element of “array”. Note that bash arrays are indexed at
#   zero, as all things should be.
#
# ${array[@]}
#   Expands “array” to its member elements as a sequence of words, one word
#   per element.
#
# ${#parameter}
#   Gives the length of “parameter”. If “parameter” is a string, this
#   expansion gives you the character length of the string. If “parameter” is
#   an array subscripted by “@” or “*” (e.g. “foo[@]”), then the expansion
#   gives you the number of elements in the array.
#
# ${parameter:offset:length}
#   A.k.a. substring expansion. If “parameter” is a string, expand up to
#   “length” characters, starting with the character at position “offset.” If
#   “offset” is unspecified, start at the first character. If “parameter” is
#   an array subscripted by “@” or “*,” (e.g. “foo[@]”) expand up to “length”
#   elements, starting at the element at position “offset” (e.g.
#   “${foo[offset]}”).
#
#   Example 1 (string):
#
#     $ foo="abcdef"
#     $ echo ${foo::3}
#     abc
#     $ echo ${foo:1:3}
#     bcd
#
#   Example 2 (array):
#
#     $ foo=("a" "b" "c" "d" "e" "f")
#     $ echo ${foo[@]::3}
#     a b c
#     $ echo ${foo[@]:1:3}
#     b c d

# According to this (https://stackoverflow.com/a/50281697) post, bash 4.3 alpha
# added the feature used in this script to pass a variable by ref.
bash_vmin=4.3.0

# Check Bash version
bash_v=$(bash --version | head -1 | grep -Eo "[0-9\.]{2,}[0-9]")
if [[ $(printf "%s\n%s\n" "$bash_vmin" "$bash_v" | sort -V | head -1) != "$bash_vmin" ]]; then
    echo "ch-completion.bash: unsupported bash version ($bash_v < $bash_vmin)"
    return 1
fi

# Check for bash completion, exit if not found. FIXME: #1640.
if [[ -z "$(declare -f -F _get_comp_words_by_ref)" ]]; then
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        . /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        . /etc/bash_completion
    else
        echo "ch-completion.bash: dependency \"bash_completion\" not found, exiting"
        return 1
    fi
fi

# Debugging log
if [[ -f "/tmp/ch-completion.log" && -n "$CH_COMPLETION_DEBUG" ]]; then
    printf "completion log\n\n" >> /tmp/ch-completion.log
fi


## ch-image ##

# Subcommands and options for ch-image
#

_image_build_opts="-b --bind --build-arg -f --file --force
                   --force-cmd -n --dry-run --parse-only -t --tag"

_image_common_opts="-a --arch --always-download --auth --cache
                    --cache-large --dependencies -h --help
                    --no-cache --no-lock --no-xattrs --profile
                    --rebuild --password-many -q --quiet -s --storage
                    --tls-no-verify -v --verbose --version --xattrs"

_image_subcommands="build build-cache delete gestalt
                    import list pull push reset undelete"

# archs taken from ARCH_MAP in charliecloud.py
_archs="amd64 arm/v5 arm/v6 arm/v7 arm64/v8 386 mips64le ppc64le s390x"

# Completion function for ch-image
#
_ch_image_complete () {
    local prev
    local cur
    local cword
    local words
    local sub_cmd
    local strg_dir
    local extras=
    _get_comp_words_by_ref -n : cur prev words cword

    sub_cmd=$(_ch_image_subcmd_get "$cword" "${words[@]}")
    # To find the storage directory, we want to look at all the words in the
    # current command line except for the current word (“${words[$cword]}”
    # here). We do this to prevent unexpected behavior resulting from the
    # current word being incomplete. The bash syntax we use to accomplish this
    # is “"${array[@]::$i}" "${array[@]:$i+1:${#array[@]}-1}"” which is
    # analagous to “array[:i] + array[i+1:]” in Python, giving you all elements
    # of the array, except for the one at index “i”. The syntax glossary at the
    # top of this file gives a breakdown of the constituent elements of this
    # hideous expression.
    strg_dir=$(_ch_find_storage "${words[@]::$cword}" "${words[@]:$cword+1:${#array[@]}-1}")

    # Populate debug log
    _DEBUG "\$ ${words[*]}"
    _DEBUG " storage: dir: $strg_dir"
    _DEBUG " word index: $cword"
    _DEBUG " current: $cur"
    _DEBUG " previous: $prev"
    _DEBUG " sub command: $sub_cmd"

    # Common opts that take args
    #
    case "$prev" in
    -a|--arch)
        COMPREPLY=( $(compgen -W "host yolo $_archs" -- "$cur") )
        return 0
        ;;
    --cache-large)
        # This is just a user-specified number. Can’t autocomplete
        COMPREPLY=()
        return 0
        ;;
    -s|--storage)
        # Avoid overzealous completion. E.g. if there’s only one subdir of the
        # current dir, this command completes to that dir even if $cur is empty
        # (i.e. the user hasn’t yet typed anything), which seems confusing for
        # the user.
        if [[ -n "$cur" ]]; then
            compopt -o nospace
            COMPREPLY=( $(compgen -d -S / -- "$cur") )
        fi
        return 0
        ;;
    esac

    case "$sub_cmd" in
    build)
        case "$prev" in
        # Go through a list of potential subcommand-specific opts to see if
        # $cur should be an argument. Otherwise, default to CONTEXT or any
        # valid option (common or subcommand-specific).
        -f|--file)
            compopt -o nospace
            COMPREPLY=( $(_compgen_filepaths "$cur") )
            return 0
            ;;
        -t)
            # We can’t autocomplete a tag, so we're not even gonna allow
            # autocomplete after this option.
            COMPREPLY=()
            return 0
            ;;
        *)
            # Autocomplete to context directory, common opt, or build-specific
            # opt --force can take “fakeroot” or “seccomp” as an argument, or
            # no argument at all.
            if [[ $prev == --force ]]; then
                extras+="$extras fakeroot seccomp"
            fi
            COMPREPLY=( $(compgen -W "$_image_build_opts $extras"  -- "$cur") )
            # By default, “complete” adds a space after each completed word.
            # This is incredibly inconvenient when completing directories and
            # filepaths, so we enable the “nospace” option. We want to make
            # sure that this option is only enabled if there are valid path
            # completions for $cur, otherwise spaces would never be added
            # after a completed word, which is also inconveninet.
            if [[ -n "$(compgen -d -S / -- "$cur")" ]]; then
                compopt -o nospace
                COMPREPLY+=( $(compgen -d -S / -- "$cur") )
            fi
            ;;
        esac
        ;;
    build-cache)
        COMPREPLY=( $(compgen -W "--reset --gc --tree --dot" -- "$cur") )
        ;;
    delete|list)
        if [[ "$sub_cmd" == "list" ]]; then
            if [[ "$prev" == "--undeletable" || "$prev" == "--undeleteable" || "$prev" == "-u" ]]; then
                COMPREPLY=( $(compgen -W "$(_ch_undelete_list "$strg_dir")" -- "$cur") )
                return 0
            fi
            extras+="$extras -l --long -u --undeletable"
            # If “cur” starts with “--undelete,” add “--undeleteable” (the less
            # correct version of “--undeletable”) to the list of possible
            # completions.
            if [[ ${cur::10} == "--undelete" ]]; then
                extras="$extras --undeleteable"
            fi
        fi
        COMPREPLY=( $(compgen -W "$(_ch_list_images "$strg_dir") $extras" -- "$cur") )
        __ltrim_colon_completions "$cur"
        ;;
    gestalt)
        COMPREPLY=( $(compgen -W "bucache bucache-dot python-path
                                  storage-path" -- "$cur") )
        ;;
    import)
        # Complete (1) directories and (2) files named like tarballs.
        COMPREPLY+=( $(_compgen_filepaths -X "!*.tar.* !*tgz" "$cur") )
        if [[ ${#COMPREPLY} -gt 0 ]]; then
            compopt -o nospace
        fi
        ;;
    push)
        if [[ "$prev" == "--image" ]]; then
            compopt -o nospace
            COMPREPLY=( $(compgen -d -S / -- "$cur") )
            return 0
        fi
        COMPREPLY=( $(compgen -W "$(_ch_list_images "$strg_dir") --image" -- "$cur") )
        __ltrim_colon_completions "$cur"
        ;;
    undelete)
        # FIXME: Update with “ch-image undelete --list” once #1551 drops
        COMPREPLY=( $(compgen -W "$(_ch_undelete_list "$strg_dir")" -- "$cur") )
        ;;
    '')
        # Only autocomplete subcommands if there's no subcommand present.
        COMPREPLY=( $(compgen -W "$_image_subcommands" -- "$cur") )
        ;;
    esac

    # If we’ve made it this far, the last remaining option for completion is
    # common opts.
    COMPREPLY+=( $(compgen -W "$_image_common_opts" -- "$cur") )
    return 0
}


## ch-run ##

# Options for ch-run
#

_run_opts="-b --bind -c --cd --env-no-expand --feature -g --gid
           --home -j --join --join-pid --join-ct --join-tag -m
           --mount --no-passwd -s --storage --seccomp -t
           --private-tmp --set-env -u --uid --unsafe --unset-env
           -v --verbose -w --write -? --help --usage -V --version"

_run_features="extglob seccomp squash" # args for the --feature option

# Completion function for ch-run
#
_ch_run_complete () {
    local prev
    local cur
    local cword
    local words
    local strg_dir
    local extras=
    _get_comp_words_by_ref -n : cur prev words cword

    # See the comment above the first call to “_ch_find_storage” for an
    # explanation of the horrible syntax here.
    strg_dir=$(_ch_find_storage "${words[@]::$cword}" "${words[@]:$cword+1:${#array[@]}-1}")
    local cli_image
    local cmd_index=-1
   _ch_run_image_finder "$strg_dir" "$cword" cli_image cmd_index "${words[@]}"

    # Populate debug log
    _DEBUG "\$ ${words[*]}"
    _DEBUG " storage: dir: $strg_dir"
    _DEBUG " word index: $cword"
    _DEBUG " current: $cur"
    _DEBUG " previous: $prev"
    _DEBUG " cli image: $cli_image"

    # Currently, we don’t try to suggest completions if you’re in the “command”
    # part of the ch-run CLI (i.e. entering commands to be run inside the
    # container). Implementing this *may* be possible, but doing so would likely
    # be absurdly complicated, so we don’t plan on it.
    if [[ $cmd_index != -1 && $cmd_index -lt $cword ]]; then
        COMPREPLY=()
        return 0
    fi

    # Common opts that take args
    #
    case "$prev" in
    -b|--bind)
        COMPREPLY=()
        return 0
        ;;
    -c|--cd)
        COMPREPLY=()
        return 0
        ;;
    --feature)
        COMPREPLY=( $(compgen -W "$_run_features" --  "$cur") )
        return 0
        ;;
    -g|--gid)
        COMPREPLY=()
        return 0
        ;;
    --join-pid)
        COMPREPLY=()
        return 0
        ;;
    --join-ct)
        COMPREPLY=()
        return 0
        ;;
    --join-tag)
        COMPREPLY=()
        return 0
        ;;
    -m|--mount)
        compopt -o nospace
        COMPREPLY=( $(compgen -d -- "$cur") )
        return 0
        ;;
    -s|--storage)
        # See comment about overzealous completion for the “--storage” option
        # under “_ch_convert_complete”.
        if [[ -n "$cur" ]]; then
            compopt -o nospace
            COMPREPLY=( $(compgen -d -S / -- "$cur") )
        fi
        return 0
        ;;
    --set-env)
        extras+=$(compgen -f -- "$cur")
        ;;
    -u|--uid)
        COMPREPLY=()
        return 0
        ;;
    --unset-env)
        COMPREPLY=()
        return 0
        ;;
    esac

    if [[ -z $cli_image ]]; then
        # No image found in command line, complete dirs, tarfiles, and sqfs
        # archives
        COMPREPLY=( $(_compgen_filepaths -X "!*.tar.* !*tgz !*.sqfs" "$cur") )
        # Complete images in storage. Note we don't use “ch-image list” here
        # because it can initialize an empty storage directory and we don't want
        # this script to have any such side effects.
        COMPREPLY+=( $(compgen -W "$(_ch_list_images "$strg_dir")" -- "$cur") )
        __ltrim_colon_completions "$cur"
    fi

    # Only use the “nospace” option when a valid path completion exists to avoid
    # the inconvenience of unnecessarily making users type in their own spaces
    # all the time.
    if [[ -n "$(_compgen_filepaths -X "!*.tar.* !*tgz !*.sqfs" "$cur")" ]]; then
        compopt -o nospace
    fi

    COMPREPLY+=( $(compgen -W "$_run_opts $extras" -- "$cur") )
    return 0
}


## Helper functions ##

_DEBUG () {
    if [[ -n "$CH_COMPLETION_DEBUG" ]]; then
        echo "$@" >> /tmp/ch-completion.log
    fi
}

# Disable completion.
ch-completion-disable () {
    complete -r ch-image
    complete -r ch-run
}

# Figure out which storage directory to use (including cli-specified storage).
# Remove trailing slash. Note that this isn't performed when the script is
# sourced because the working storage directory can effectively change at any
# time with “CH_IMAGE_STORAGE” or the “--storage” option.
_ch_find_storage () {
    if echo "$@" | grep -Eq -- '\s(--storage|-\w*s)'; then
        # This if “--storage” or “-s” are in the command line.
        sed -Ee 's/(.*)(--storage=*|[^-]-s=*)\ *([^ ]*)(.*$)/\3/g' -Ee 's|/$||g' <<< "$@"
    elif [[ -n "$CH_IMAGE_STORAGE" ]]; then
        echo "$CH_IMAGE_STORAGE" | sed -Ee 's|/$||g'
    else
        echo "/var/tmp/$USER.ch"
    fi
}

# List images in storage directory.
_ch_list_images () {
    # “find” throws an error if “img” subdir doesn't exist or is empty, so check
    # before proceeding.
    if [[ -d "$1/img" && -n "$(ls -A "$1/img")" ]]; then
        find "$1/img/"* -maxdepth 0 -printf "%f\n" | sed -e 's|+|:|g' -e 's|%|/|g'
    fi
}

# Print the subcommand in an array of words; if there is not one, print an empty
# string. This feels a bit kludge-y, but it's the best I could come up with.
# It's worth noting that the double for loop doesn't take that much time, since
# the Charliecloud command line, even in the wost case, is relatively short.
#
# Usage: _ch_image_subcmd_get [words]
#
# Example:
#   >> _ch_image_subcmd_get "ch-image [...] build [...]"
#   build
_ch_image_subcmd_get () {
    local cword="$1"
    shift 1
    local subcmd
    local wrds=("$@")
    local ct=1

    while ((ct < ${#wrds[@]})); do
        if [[ $ct != "$cword" ]]; then
            for subcmd_i in $_image_subcommands; do
                if [[ "${wrds[$ct]}" == "$subcmd_i" ]]; then
                    subcmd="$subcmd_i"
                    break 2
                fi
            done
        fi
        ((ct++))
    done
    echo "$subcmd"
}

# Horrible, disgusting function to find an image or image ref in the ch-run
# command line. This function takes five arguments:
#
#   1.) A string representing the path to the storage directory.
#
#   2.) The current position (measured in words) of the cursor in the array
#       representing the command line (index starting at 0).
#
#   3.) An out parameter (explanation below). If “_ch_run_image_finder” finds
#       the name of an image in storage (e.g. “alpine:latest”) or something that
#       looks like an image path (i.e. a directory, tarball or file named like a
#       squash archive) in the command line, the value of the variable will be
#       updated to the image name or path. If neither are found, the function
#       will not modify the value of this variable.
#
#   4.) Another out parameter. If this function finds “--” in the current
#       command line and it doesn't seem like the user is trying to complete
#       that “--” to an option, “_ch_run_image_finder” will assume that this is
#       the point beyond which the user specifies commands to be run inside the
#       container and will give the variable the index value of the “--”. Our
#       criterion for deciding that the user isn't trying to complete “--” to an
#       option is that the current index of the cursor in the word array
#       (argument 2, see above) is not equal to the position of the “--” in said
#       array.
#
#   5.) A string representing the expanded command line array (i.e.
#       "${array[@]}").
#
# “Out parameter” here means a variable that is meant to pass information from
# this function to its caller (the “_ch_run_complete” function). Out parameters
# should be passed to “_ch_run_image_finder” as the unquoted names of variables
# (e.g. “var” instead of “$var” or “"$var"”). Passing the variables to
# “_ch_run_image_finder” in this way allows it to change their values, and for
# those changes to persist in the scope that called the function (this is what
# makes them “out parameters”).
#
_ch_run_image_finder () {
    # The essential purpose of this function is to try to find an image in the
    # current command line. If it finds one, it passes the “name” of the image
    # back to the caller in the form of an out parameter (see above). If it
    # doesn't find one, the out parameter remains unmodified. This function
    # assumes that the out parameter in question is the empty string before it
    # gets called.
    local images                   # these two lines are separate b/c SC2155
    images=$(_ch_list_images "$1") #
    shift 1
    local cword="$1"
    shift 1
    local -n cli_img=$1
    local -n cmd_pt=$2
    shift 2
    local wrds=("$@")
    local ct=1

    # Check for tarballs and squashfs archives.
    while ((ct < ${#wrds[@]})); do
        # In bash, expansion of the “~” character to the value of $HOME doesn't
        # happen if a value is quoted (see
        # https://stackoverflow.com/a/52519780). To work around this, we add
        # “eval echo” (https://stackoverflow.com/a/6988394) to this test.
        if [[ $ct != "$cword" ]]; then
            if [[    (    -f "$(_sanitized_tilde_expand "${wrds[$ct]}")" \
                    && (       ${wrds[$ct]} == *.sqfs \
                            || ${wrds[$ct]} == *.tar.? \
                            || ${wrds[$ct]} == *.tar.?? \
                            || ${wrds[$ct]} == *.tgz ) ) \
                || (    -d ${wrds[$ct]} \
                    && ${wrds[$ct-1]} != --mount \
                    && ${wrds[$ct-1]} != -m \
                    && ${wrds[$ct-1]} != --bind \
                    && ${wrds[$ct-1]} != -b \
                    && ${wrds[$ct-1]} != -c \
                    && ${wrds[$ct-1]} != --cd ) ]]; then
                cli_img="${wrds[$ct]}"
            fi
            if [[ ${wrds[$ct]} == "--" ]]; then
                cmd_pt=$ct
            fi
            # Check for refs to images in storage.
            if [[ -z $cli_img ]]; then
                for img in $images; do
                    if [[ ${wrds[$ct]} == "$img" ]]; then
                        cli_img="${wrds[$ct]}"
                    fi
                done
            fi
        fi
        ((ct++))
    done
}

# List undeletable images in the build cache, if it exists.
_ch_undelete_list () {
    if [[ -d "$1/bucache/" ]]; then
        git -C "$strg_dir/bucache/" tag -l | sed -e "s/&//g" \
                                                 -e "s/%/\//g" \
                                                 -e "s/+/:/g"
    fi
}

# Returns filenames and directories, appending a slash to directory names.
# This function takes option “-X”, a string of space-separated glob patterns
# to be excluded from file completion using the compgen option of the same
# name (source: https://stackoverflow.com/a/40227233, see also:
# https://devdocs.io/bash/programmable-completion-builtins#index-compgen)
_compgen_filepaths() {
    local filterpats=("")
    if [[ "$1" == "-X" && 1 -lt ${#@} ]]; then
        # Read a string into an array:
        #   https://stackoverflow.com/a/10586169
        # Pitfalls:
        #   https://stackoverflow.com/a/45201229
        # FIXME: Need to modify $IFS before doing this?
        read -ra filterpats <<< "$2"
        shift 2
    fi

    local cur="$1"

    # Files, excluding directories, with no trailing slashes. The grep
    # performs an inverted substring match on the list of directories and the
    # list of files respectively produced by compgen. The compgen statements
    # also prepend (-P) a “^” and append (-S) a “$” to the file/dir names to
    # avoid the case where a substring matching a dirname is erroniously
    # removed from a filename by the inverted match. These delimiters are then
    # removed by the “sed”. (See the StackOverflow post cited above for OP’s
    # explanation of this code). The for loop iterates through exclusion
    # patterns specified by the “-X” option. If “-X” isn't specified, the code
    # in the loop executes once, with no patterns excluded (“-X ""”).
    for pat in "${filterpats[@]}"
    do
        grep -v -F -f <(compgen -d -P ^ -S '$' -X "$pat" -- "$cur") \
            <(compgen -f -P ^ -S '$' -X "$pat" -- "$cur") |
            sed -e 's/^\^//' -e 's/\$$/ /'
    done

    # Directories with trailing slashes:
    compgen -d -S / -- "$cur"
}

# Expand tilde in quoted strings to the correct home path, if applicable, while
# sanitizing to prevent code injection (see https://stackoverflow.com/a/38037679).
#
_sanitized_tilde_expand () {
    if [[ $1 == ~* ]]; then
        # Adding the “/” at the end here is important for ensuring that the “~”
        # always gets expanded, e.g. in the case where "$1" is “~” instead of
        # “~/”.
        user="$(echo "$1/" | sed -E 's|^~([^~/]*/).*|\1|g')"
        path="$(echo "$1" | sed -E 's|^~[^~/]*(.*)|\1|g')"
        eval "$(printf "home=~%q" "$user")"
        # Check if “home” is a vaild directory.
        # shellcheck disable=SC2154
        if [[ -d "$home" ]]; then
            # The first character of “path” is “/”. Since we've added a “/” to
            # the end of “home” for proper “~” expansion, we now avoid the first
            # character of “path” in the concatenation of the two to avoid a
            # “//”.
            echo "$home${path:1:${#path}-1}"
            return 0
        fi
    fi
    echo "$1"
}

complete -F _ch_image_complete ch-image
complete -F _ch_run_complete ch-run
