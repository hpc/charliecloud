load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    if [[ -z "${ch_lustre}" ]]; then
        skip 'no lustre to bind mount'
    fi
    prerequisites_ok lustre

    # Check lustre directory exists
    if [[ ! -e "$ch_lustre" ]]; then
        skip "${ch_lustre} does not exist"
    fi
    # Check lustre directory is a directory
    if [[ ! -d "$ch_lustre" ]]; then
        skip "${ch_lustre} is not a directory"
    fi
}

@test "${ch_tag}/write" {
    binds=${ch_lustre}:/lustre
    ch-run -b "$binds" "$ch_img" -- touch /lustre/test_w.txt
    ch-run -b "$binds" "$ch_img" -- echo "hello" /lustre/test_w.txt
}

@test "${ch_tag}/read" {
    binds=${ch_lustre}:/lustre
    ch-run -b "$binds" "$ch_img" -- cat /lustre/test_w.txt > /dev/null
}

@test "${ch_tag}/set_stripe_get_stripe" {
    binds=${ch_lustre}:/lustre
    ch-run -b "$binds" "$ch_img" -- mkdir /lustre/default_stripes
    ch-run -b "$binds" "$ch_img" -- lfs getstripe /lustre/default_stripes
    ch-run -b "$binds" "$ch_img" -- mkdir /lustre/four_stripes
    ch-run -b "$binds" "$ch_img" -- lfs setstripe -c 4 /lustre/four_stripes
}
