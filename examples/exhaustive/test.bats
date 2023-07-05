CH_TEST_TAG=$ch_test_tag
load "${CHTEST_DIR}/common.bash"

setup () {
    scope standard
    prerequisites_ok exhaustive
}

@test "${ch_tag}/WORKDIR" {
    output_expected=$(cat <<'EOF'
/workdir:
abs2
file

/workdir/abs2:
file
rel1

/workdir/abs2/rel1:
file1
file2
rel2

/workdir/abs2/rel1/rel2:
file
EOF
)
    run ch-run "$ch_img" -- ls -R /workdir
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$output_expected") <(echo "$output")
}
