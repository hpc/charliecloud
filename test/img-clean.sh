while true; do
	img_ct=$(img ls | tail -n +2 | wc -l)
	[[ 0 -eq $img_ct ]] && break
	echo "Found $img_ct images"
	# shellcheck disable=SC2046
	img ls | tail -n +2 |  awk '{ print $1 }' | head -n 1 | xargs img rm
done
