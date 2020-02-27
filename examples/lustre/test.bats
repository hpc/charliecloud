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

binds=${ch_lustre}:/mnt/0
work_dir=/mnt/0/charliecloud_test
mkdir -p "${ch_lustre}/charliecloud_test"

@test "${ch_tag}/start clean" {
    clean_dir "${ch_lustre}/charliecloud_test" || true
}

@test "${ch_tag}/create directory" {
    ch-run -b "$binds" "$ch_img" -- mkdir "${work_dir}/test_create_dir"
}

@test "${ch_tag}/create file" {
    ch-run -b "$binds" "$ch_img" -- touch "${work_dir}/test_create_file"
}

@test "${ch_tag}/delete file" {
    ch-run -b "$binds" "$ch_img" -- rm "${work_dir}/test_create_file"
}

@test "${ch_tag}/write file" {
    # sh wrapper to get echo output to the right place
    # without it, the output from echo goes outside the container
    ch-run -b "$binds" "$ch_img" -- sh -c "echo hello > ${work_dir}/test_write.txt"
}

@test "${ch_tag}/read file" {
    output_expected=$(cat <<'EOF'
hello
0+1 records in
0+1 records out
EOF
)
    # using dd allows us to skip the read cache and hit the disk
    run ch-run -b "$binds" "$ch_img" -- dd if="${work_dir}/test_write.txt" iflag=nocache status=noxfer
    diff <(echo "$output_expected") <(echo "$output")
}

@test "${ch_tag}/striping" {
    ch-run -b "$binds" "$ch_img" -- mkdir "${work_dir}/set_stripes"
    ch-run -b "$binds" "$ch_img" -- lfs setstripe -c 1 "${work_dir}/set_stripes"
    run ch-run -b "$binds" "$ch_img" -- lfs getstripe "${work_dir}/set_stripes/"

    output_expected="$output"
    ch-run -b "$binds" "$ch_img" -- lfs setstripe -c 4 "${work_dir}/set_stripes"
    run ch-run -b "$binds" "$ch_img" -- lfs getstripe "${work_dir}/set_stripes"
    run diff -u <(echo "$output_expected") <(echo "$output")
    [[ $status -ne 0 ]]
}

@test "${ch_tag}/clean up" {
    clean_dir "${ch_lustre}/charliecloud_test"
}
