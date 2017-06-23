load ../../../test/common

@test 'ch-run $EXAMPLE_TAG ' {
	ch-run $EXAMPLE_IMG -- echo "this container is from dockerhub"
}
