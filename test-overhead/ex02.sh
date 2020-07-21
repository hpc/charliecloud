#!/bin/bash


#create schema
printf "ID, E2E-TG1, E2E-TG2, E2E-TG3, MT-TG2, MT-TG3, UT-TG2, UT-TG3, RT-TG1, RT-TG2, RT-TG3\n" > ex02.csv



#repeat 1000 times
for i in {1..1000}
do

#Write ID
printf "$i," > ex02.csv

#Time E2E for each Test Group


#Mount Times





#Unmount Times



#RunTimes













done

