#!/bin/bash

#SBATCH --job-name=ch-runWorkflowTest
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=chernikov@lanl.gov


./ex02.sh
