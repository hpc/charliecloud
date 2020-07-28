#!/bin/bash


f=$(tail -n +2 ex01-files.csv)
while IFS=, read -r i bytes file

do

ID="ex01-"$i""
./ex02.sh "$ID" 2 "$file"

done <<< "$f"

