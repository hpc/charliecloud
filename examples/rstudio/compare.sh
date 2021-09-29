#!/bin/bash
percent_diff=$(compare -metric MSE "$1" "$2" null: 2>&1 > /dev/null | awk '{print $1}')
if [[ $percent_diff == 0 ]];then
    echo "Images are equal"
else
    echo "Images don't match"
fi
