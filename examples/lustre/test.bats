load "${CHTEST_DIR}/common.bash"

setup () {
    scope full
    prerequisites_ok lustre
    
    if [[ $SLURM_JOB_ID ]]; then
        if [[ -z $ch_lustre ]]; then
            pedantic_fail 'no lustre to bind mount'
        fi
    else
        if [[ -z $ch_lustre ]]; then
            skip 'no lustre to bind mount'
        fi
    fi
    
    # Check lustre directory exists
    if [[ ! -e $ch_lustre ]]; then
        echo "${ch_lustre} does not exist"
        exit 1
    fi
    # Check lustre directory is a directory
    if [[ ! -d $ch_lustre ]]; then
        echo "${ch_lustre} is not a directory"
        exit 1
    fi

    binds=${ch_lustre}:/mnt/0
    work_dir = $(mktemp -d --tmpdir=${ch_lustre} ch-test.XXXXXX)
}

@test "${ch_tag}/create dir" {
    ch-run -b "$binds" "$ch_img" -- mkdir "$work_dir"
}

@test "${ch_tag}/create file" {
    ch-run -b "$binds" "$ch_img" -- touch "${work_dir}/test_create.txt"
}

@test  "${ch_tag}/delete file" { 
    ch-run -b "$binds" "$ch_img" -- rm -f "${work_dir}/test_create.txt"
}

@test "${ch_tag}/write" {
    ch-run -b "$binds" "$ch_img" -- echo "hello" > "${work_dir}/test_write.txt"
}

@test "${ch_tag}/read" {
    run ch-run -b "$binds" "$ch_img" -- cat "${work_dir}/test_write.txt"
    [[ $output -eq hello ]] || echo "Content of ${work_dir}/test_write.txt invalid" && exit 1
}

@test "${ch_tag}/striping {
    ch-run -b "$binds" "$ch_img" -- mkdir "${work_dir}/set_stripes"
    ch-run -b "$binds" "$ch_img" -- lfs setstripe -c 1 "${work_dir}/set_stripes
    one_stripe=$(ch-run -b "$binds" "$ch_img" -- lfs getstripe "${work_dir}/set_stripes/" | grep stripe_count | gawk '{ print $2}')
    [[ $one_stripe -eq 1 ]] || echo "Could not set stripe pattern to 1" && exit 1
    ch-run -b "$binds" "$ch_img" -- lfs setstripe -c 4 "${work_dir}/set_stripes
    four_stripes=$(ch-run -b "$binds" "$ch_img" -- lfs getstripe "${work_dir}/set_stripes" | grep stripe_count | gawk '{ print $2}')
    [[ $four_stripes -eq 4 ]] || echo "Could not set stripe pattern to 4" && exit 1
}

@test "${ch_tag}/clean up {
    ch-run -b "$binds" "$ch_img" -- rmdir "${work_dir}/set_stripes"
    ch-run -b "$binds" "$ch_img" -- rm -f "${work_dir}/test_write.txt"
    ch-run -b "$binds" "$ch_img" -- rmdir "$work_dir"
}