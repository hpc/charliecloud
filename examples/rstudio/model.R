# This example R script builds a linear model of distance vs speed 
# using the cars dataset then plots it.

args <- commandArgs(trailingOnly = TRUE)
# Load vehicle data
data(cars)

# Create linear model
lm <- lm(dist~speed, cars)

# plot linear model results
png('/mnt/0/plot.png')
plot(lm, 1)
