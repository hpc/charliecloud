#!/bin/bash


while IFS=, read -r bytes file

do

./ex02.sh ex01-"$bytes" 30 $file

done < ex01-files.csv

