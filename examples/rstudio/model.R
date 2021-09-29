#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
# Load vehicle data
data(cars)

# Create linear model
lm <- lm(dist~speed, cars)

# plot linear model results
png(args[1])
plot(lm, 1)
