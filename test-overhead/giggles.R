library(dplyr)
library(ggplot2)
library(reshape2)
require(graphics)

e2e <- read.csv('giggles.csv')
# Plot End to End Times Raw
e2e <- e2e %>%
    mutate(e2e.sfsh = end.sfsh-start.sfsh) %>%
    mutate(e2e.sfsl = end.sfsl-start.sfsl) %>%
    mutate(e2e.psfsh = end.psfsh-start.psfsh) %>%
    mutate(e2e.tb = end.tb-start.tb) %>%
    select(e2e.sfsh, e2e.sfsl, e2e.psfsh, e2e.tb)
names(e2e) <- c("Old SquashFS Workflow (High Level)",
    "Old SquashFS Workflow (Low Level)",
    "New SquashFS Workflow(High Level)",
    "Tar Ball Workflow")
ggplot(melt(e2e), aes(x=value, y=variable, fill=variable)) + geom_boxplot() +
    scale_y_discrete(labels=abbreviate) +
    labs(title="Charliecloud Container Run Workflows") +
    labs(x="Duration (s)", y="Workflow") +
    scale_fill_manual(values=palette(), name = "Worfklow")


