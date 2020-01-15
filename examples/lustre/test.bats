load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    if [ -z "${ch_lustre}" ]; then
        skip 'no lustre to bind mount'
    fi
    prerequisites_ok lustre

    # Check lustre directory exists
    if [ ! -e "$ch_lustre" ]; then
        skip "${ch_lustre} does not exist"
    fi
    # Check lustre directory is a directory
    if [ ! -d "$ch_lustre" ]; then
        skip "${ch_lustre} is not a directory"
    fi
}

@test "${ch_tag}/write" {
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- echo "hello" /lustre/test_w.txt
}

@test "${ch_tag}/read" {
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- cat /lustre/test_w.txt > /dev/null
}

@test "${ch_tag}/modify_stripes" {
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- mkdir /lustre/default_stripes
    run ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- lfs getstripe /lustre/default_stripes
    default=$(echo "${output}" | grep stripe_count | gawk '{print $2}')
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- mkdir /lustre/four_stripes
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- lfs setstripe -c 4 /lustre/four_stripes
    run ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- lfs getstripe /lustre/four_stripes
    stripes=$(echo "${output}" | grep stripe_count | gawk '{print $2}')

    [[ ! "${stripes}" = "${default}" ]] 
    
    # Ensure striping applies to file
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- dd if=/dev/zero of=/lustre/four_stripes/test.t bs=1M count=10
    run ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- lfs getstripe /lustre/four_stripes/test.t | grep stripe_count | gawk '{ print $2}'
    [[ $output == 4 ]]
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- cp /lustre/four_stripes/test.t /lustre/default_stripes
    run ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- lfs getstripe /lustre/default_stripes/test.t | grep stripe_count | gawk '{ print $2}'
    [[ "${output}" == "${default_stripes}" ]]

    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- rm /lustre/default_stripes/test.t
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- rm /lustre/four_stripes/test.t 
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- rmdir /lustre/four_stripes
    ch-run -b "${ch_lustre}:/lustre" "$ch_img" -- rmdir /lustre/default_stripes
}
