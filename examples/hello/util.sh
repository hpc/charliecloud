print_info () {
    printf 'distro: '
    cat /etc/os-release /etc/*-release /etc/*_version \
        2> /dev/null \
        | egrep '[A-Za-z] [0-9]' \
        | head -1

    printf 'userns: '
    ls -l /proc/self/ns/user | sed 's/^.\+-> user:\[\([0-9]\+\)\]/\1/'
}
