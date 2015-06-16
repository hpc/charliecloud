#!/bin/sh

set -e
set -x

DATA1=/ch/data1
DATA2=/ch/data2
BONNIE_OPTS="-q -u0:0 -s32g:1024k"

# Performance tests

# CPU (integer)
#sysbench --test=cpu run | tee $DATA1/bench_cpu.out

# Memory
#sysbench --test=memory run | tee $DATA1/bench_cup.out

# I/O against /ch/tmp (virtual block device) (cold, i.e. requires allocation)
#rm -vf $DATA1/bonnie.csv
#bonnie++ -m tmp-cold $BONNIE_OPTS -d $DATA2 >> $DATA1/bonnie.csv

# I/O against /ch/tmp (allocated)
#bonnie++ -m tmp-warm $BONNIE_OPTS -d $DATA2 >> $DATA1/bonnie.csv

# I/O against /ch/data1 (9p filesystem passthrough)
bonnie++ -m 9p $BONNIE_OPTS -d $DATA2 >> $DATA1/bonnie.csv
