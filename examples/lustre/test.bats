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

    # Check lustre directory is a directory
    if [[ ! -d $ch_lustre ]]; then
        echo "${ch_lustre} is not a directory"
        exit 1
    fi
}

clean_dir () {
    rmdir "${1}/set_stripes"
    rmdir "${1}/test_create_dir"
    rm "${1}/test_write.txt"
    rmdir "$1"
}

tidy_run () {
    ch-run -b "$binds" "$ch_img" -- "$@"
}

binds=${ch_lustre}:/mnt/0
work_dir=/mnt/0/charliecloud_test

@test "${ch_tag}/start clean" {
    clean_dir "${ch_lustre}/charliecloud_test" || true
    mkdir -p "${ch_lustre}/charliecloud_test"
}

@test "${ch_tag}/create directory" {
    tidy_run mkdir "${work_dir}/test_create_dir"
}

@test "${ch_tag}/create file" {
    tidy_run touch "${work_dir}/test_create_file"
}

@test "${ch_tag}/delete file" {
    tidy_run rm "${work_dir}/test_create_file"
}

@test "${ch_tag}/write file" {
    # sh wrapper to get echo output to the right place. Without it, the output
    # from echo goes outside the container.
    tidy_run sh -c "echo hello > ${work_dir}/test_write.txt"
}

@test "${ch_tag}/read file" {
    output_expected=$(cat <<'EOF'
hello
0+1 records in
0+1 records out
EOF
)
    # Using dd allows us to skip the write cache and hit the disk.
    run tidy_run dd if="${work_dir}/test_write.txt" iflag=nocache status=noxfer
    diff -u <(echo "$output_expected") <(echo "$output")
}

@test "${ch_tag}/striping" {
    tidy_run mkdir "${work_dir}/set_stripes"
    stripe_ct_old=$(tidy_run lfs getstripe --stripe-count "${work_dir}/set_stripes/")
    echo "old stripe count: $stripe_ct_old"
    expected_new=$((stripe_ct_old * 2))
    echo "expected new stripe count: $expected_new"
    tidy_run lfs setstripe -c "$expected_new" "${work_dir}/set_stripes"
    stripe_ct_new=$(tidy_run lfs getstripe --stripe-count "${work_dir}/set_stripes")
    echo "actual new stripe count: $stripe_ct_new"
    [[ $expected_new -eq $stripe_ct_new ]]
}

@test "${ch_tag}/clean up" {
    clean_dir "${ch_lustre}/charliecloud_test"
}
