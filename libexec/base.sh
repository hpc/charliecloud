set -e

# shellcheck disable=SC2034
ch_bin="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034
ch_base=${ch_bin%/*}

libexec="${ch_bin}/../libexec/charliecloud"
. "${libexec}/version.sh"


# Don't call in a subshell or the selection will be lost.
builder_choose () {
    if [ -z "$CH_BUILDER" ]; then
        if ( command -v docker >/dev/null 2>&1 ); then
            export CH_BUILDER=docker
        else
            export CH_BUILDER=ch-grow
        fi
    fi
    case $CH_BUILDER in
        buildah|buildah-runc|buildah-setuid|ch-grow|docker)
            ;;
        *)
            echo "unknown builder: $CH_BUILDER" 1>&2
            exit 1
            ;;
    esac
}

parse_basic_args () {
    if [ "$#" -eq 0 ]; then
        usage 1
    fi
    for i in "$@"; do
        if [ "$i" = --help ]; then
            usage 0
        fi
        if [ "$i" = --libexec-path ]; then
            echo "$libexec"
            exit 0
        fi
        if [ "$1" = --version ]; then
            version
        fi
    done
}

# Convert container registry path to filesystem compatible path.
tag_to_path () {
    echo "$1" | sed 's/\//./g'
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
        # shellcheck disable=SC2059
        printf "%-${desc_width}s %s (%s)\n" "$var_desc" "$value" "$method"
    fi
}


# Do we need sudo to run docker?
if ( docker info > /dev/null 2>&1 ); then
    docker_ () {
        docker "$@"
    }
else
    docker_ () {
        sudo docker "$@"
    }
fi

# Use parallel gzip if it's available.
if ( command -v pigz >/dev/null 2>&1 ); then
    gzip_ () {
        pigz "$@"
    }
else
    gzip_ () {
        gzip "$@"
    }
fi

# Use fuse low-level API if it's available.
if ( command -v squashfuse_ll >/dev/null 2>&1 ); then
    squashfuse_ () {
        squashfuse_ll "$@"
    }
else
    squashfuse_ () {
        echo "WARNING:" 1>&2
        echo "Low-level FUSE API unavailable; squashfuse will be slower" 1>&2
        squashfuse "$@"
    }
fi

# Use pv to show a progress bar, if it's available. (We also don't want a
# progress bar if stdin is not a terminal, but pv takes care of that.)
if ( command -v pv >/dev/null 2>&1 ); then
    pv_ () {
        pv -pteb "$@"
    }
else
    pv_ () {
        # Arguments may be present, but we ignore them.
        cat
    }
fi
