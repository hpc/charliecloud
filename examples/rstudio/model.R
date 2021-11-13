# Build a linear regression model of distance vs. speed using the sample cars
# dataset that comes with R, then print a summary of the model and plot it.

data(cars)

m <- lm(dist~speed, cars)
summary(m)

png('/mnt/0/plot.png')
plot(m, 1)
