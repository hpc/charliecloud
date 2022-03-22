# shellcheck shell=sh
set -e

# shellcheck disable=SC2034
ch_bin="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034
ch_base=${ch_bin%/*}

lib="${ch_bin}/../lib/charliecloud"
. "${lib}/version.sh"


# Verbosity level; works the same as the Python code.
verbose=0

DEBUG () {
    if [ "$verbose" -ge 2 ]; then
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
    # shellcheck disable=SC2059
    printf "$@" 1>&2
    printf '\n' 1>&2
}

VERBOSE () {
    if [ "$verbose" -ge 1 ]; then
        # shellcheck disable=SC2059
        printf "$@" 1>&2
        printf '\n' 1>&2
    fi
}

# Return success if path $1 exists, without dereferencing links, failure
# otherwise. ("test -e" dereferences.)
exist_p () {
    stat "$1" > /dev/null 2>&1
}

# Try to parse $1 as a common argument. If accepted, either exit (for things
# like --help) or return success; otherwise, return failure (i.e., not a
# common argument).
parse_basic_arg () {
    case $1 in
        --_lib-path)  # undocumented
            echo "$lib"
            exit 0
            ;;
        --help)
            usage 0   # exits
            ;;
        -v|--verbose)
            verbose=$((verbose+1))
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

# Convert container registry path to filesystem compatible path.
#
# NOTE: This is used both to name user-visible stuff like tarballs as well as
# dig around in the ch-image storage directory.
tag_to_path () {
    echo "$1" | tr '/' '%'
}

usage () {
    echo "${usage:?}" 1>&2
    exit "${1:-1}"
}

version () {
    # shellcheck disable=SC2154
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
#   $5: boolean:  if true, suppress chatter
#   $6: int:      width of description (use -1 for natural width)
#   $7: string:   human readable description for stdout
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


# Do we need sudo to run docker?
if docker info > /dev/null 2>&1; then
    docker_ () {
        docker "$@"
    }
else
    docker_ () {
        sudo docker "$@"
    }
fi

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

# Use pv to show a progress bar, if it's available. (We also don't want a
# progress bar if stdin is not a terminal, but pv takes care of that.)
if command -v pv > /dev/null 2>&1; then
    pv_ () {
        pv -pteb "$@"
    }
else
    pv_ () {
        # Arguments may be present, but we ignore them.
        cat
    }
fi
