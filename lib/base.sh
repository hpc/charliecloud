# shellcheck shell=sh
set -e

ch_bin="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034
ch_base=${ch_bin%/*}

ch_lib=${ch_bin}/../lib
. "${ch_lib}/version.sh"


# Log level. Incremented by “--verbose” and decremented by “--quiet”, as in the
# Python code.
log_level=0

# Logging functions. Note that we disable SC2059 because we want these functions
# to behave exactly like printf(1), e.g. we want
#
#   >>> VERBOSE "foo %s" "bar"
#   foo bar
#
# Implementing the suggestion in SC2059 would instead result in something like
#
#   >>> VERBOSE "foo %s" "bar"
#   foo %s
#   bar

DEBUG () {
    if [ "$log_level" -ge 2 ]; then
        # shellcheck disable=SC2059
        printf "$@" 1>&2
        printf '\n' 1>&2
    fi
}

FATAL () {
    printf 'error: ' 1>&2
    # shellcheck disable=SC2059
    printf "$@" 1>&2
    printf '\n' 1>&2
    exit 1
}

INFO () {
    if [ "$log_level" -ge 0 ]; then
        # shellcheck disable=SC2059
        printf "$@" 1>&2
        printf '\n' 1>&2
    fi
}

VERBOSE () {
    if [ "$log_level" -ge 1 ]; then
        # shellcheck disable=SC2059
        printf "$@" 1>&2
        printf '\n' 1>&2
    fi
}

WARNING () {
    if [ "$log_level" -ge -1 ]; then
        printf 'warning: ' 1>&2
        # shellcheck disable=SC2059
        printf "$@" 1>&2
        printf '\n' 1>&2
    fi
}

# Return success if path $1 exists, without dereferencing links, failure
# otherwise. (“test -e” dereferences.)
exist_p () {
    stat "$1" > /dev/null 2>&1
}

# Try to parse $1 as a common argument. If accepted, either exit (for things
# like --help) or return success; otherwise, return failure (i.e., not a
# common argument).
parse_basic_arg () {
    case $1 in
        --_lib-path)  # undocumented
            echo "$ch_lib"
            exit 0
            ;;
        --help)
            usage 0   # exits
            ;;
        -q|--quiet)
            if [ $log_level -gt 0 ]; then
                FATAL "incompatible options: --quiet, --verbose"
            fi
            log_level=$((log_level-1))
            return 0
            ;;
        -v|--verbose)
            if [ $log_level -lt 0 ]; then
                FATAL "incompatible options: --quiet, --verbose"
            fi
            log_level=$((log_level+1))
            return 0
            ;;
        --version)
            version   # exits
            ;;
    esac
    return 1  # not a basic arg
}

parse_basic_args () {
    if [ "$#" -eq 0 ]; then
        usage 1
    fi
    for i in "$@"; do
        parse_basic_arg "$i" || true
    done
}

# Redirect standard streams (or not) depending on “quiet” level. See table in
# FAQ.
quiet () {
    if [ $log_level -lt -2 ]; then
        "$@" 1>/dev/null 2>/dev/null
    elif [ $log_level -lt -1 ]; then
        "$@" 1>/dev/null
    else
        "$@"
    fi
}

# Convert container registry path to filesystem compatible path.
#
# NOTE: This is used both to name user-visible stuff like tarballs as well as
# dig around in the ch-image storage directory.
tag_to_path () {
    echo "$1" | tr '/:' '%+'
}

usage () {
    echo "${usage:?}" 1>&2
    exit "${1:-1}"
}

version () {
    echo 1>&2 "$ch_version"
    exit 0
}


# Set a variable and print its value, human readable description, and origin.
# Parameters:
#
#   $1: string:   variable name
#   $2: string:   command line argument value (1st priority)
#   $3: string:   environment variable value (2nd priority)
#   $4: string:   default value (3rd priority)
#   $5: int:      width of description (use -1 for natural width)
#   $6: string:   human readable description for stdout
#   $7: boolean:  if true, suppress chatter
#
# FIXME: Shouldn't export the variable, and no Bash indirection available.
# There are safe eval solution out there, but I was too lazy to deal with it.
vset () {
    var_name=$1
    cli_value=$2
    env_value=$3
    def_value=$4
    desc_width=$5
    var_desc=$6
    quiet=$7
    if   [ "$cli_value" ]; then
        export "$var_name"="$cli_value"
        value=$cli_value
        method='command line'
    elif [ "$env_value" ]; then
        export "$var_name"="$env_value"
        value=$env_value
        method='environment'
    else
        export "$var_name"="$def_value"
        value=$def_value
        method='default'
    fi
    # FIXME: Kludge: Assume it's a boolean variable and the empty string means
    # false. Print "no" instead of the empty string.
    if [ -z "$value" ]; then
        value=no
    fi
    if [ -z "$quiet" ]; then
        var_desc="$var_desc:"
        printf "%-*s %s (%s)\n" "$desc_width" "$var_desc" "$value" "$method"
    fi
}

# Is Docker present, and if so, do we need sudo? If docker is a wrapper for
# podman, “docker info” hangs (#1656), so treat that as not found.
if    ( ! command -v docker > /dev/null 2>&1 ) \
   || ( docker --help 2>&1 | grep -Fqi podman ); then
    docker_ () {
        echo 'docker not found; unreachable code reached' 1>&1
        exit 1
    }
elif docker info > /dev/null 2>&1; then
    docker_ () {
        docker "$@"
    }
else
    docker_ () {
        sudo docker "$@"
    }
fi

# Wrapper for rootless podman (for consistency w/ docker).

# The only thing we're really concerned with here is the trailing underscore,
# since we use it to construct function calls.
podman_ () {
    podman "$@"
}

# Use parallel gzip if it's available.
if command -v pigz > /dev/null 2>&1; then
    gzip_ () {
        pigz "$@"
    }
else
    gzip_ () {
        gzip "$@"
    }
fi

# Use pv(1) to show a progress bar, if it’s available and the quiet level is
# less than one, otherwise cat(1). WARNING: You must pipe in the file because
# arguments are ignored if this is cat(1). (We also don’t want a progress bar if
# stdin is not a terminal, but pv takes care of that). Note that we put the if
# statement in the scope of the function because doing so ensures that it gets
# evaulated after “quiet” is assigned an appropriate value by “parse_basic_arg”.
pv_ () {
    if command -v pv > /dev/null 2>&1 && [ "$log_level" -gt -1 ]; then
        pv -pteb "$@"
    else
        cat
    fi
}
