library(dplyr)
library(reshape2)
library(ggplot2)
library(expss)
library(timelineS)
library(tidyr)
library(plyr)

e2e <- read.csv('ex02-E2E.csv')
broken <- read.csv('ex02.csv')

#W R A N G L E

broken <-broken %>% mutate(E2E.TG2A.Sum = MT.TG2A + RT.TG2A + UT.TG2A)
broken <- broken %>% mutate(E2E.TG2B.Sum = MT.TG2B + RT.TG2B + UT.TG2B) 
broken <-broken %>% mutate(E2E.TG3.Sum = MT.TG3 + RT.TG3 + UT.TG3) 
all <- cbind(select(broken, -ID), select(e2e, -ID))
scaleFactorTG2A <- mean(all$E2E.TG2A) / mean(all$E2E.TG2A.Sum)
scaleFactorTG2B <- mean(all$E2E.TG2B) / mean(all$E2E.TG2B.Sum)
scaleFactorTG3 <- mean(all$E2E.TG3) / mean(all$E2E.TG3.Sum)

all$MT.TG3 <- all$MT.TG3 * scaleFactorTG3
all$RT.TG3 <- all$RT.TG3 * scaleFactorTG3
all$UT.TG3 <- all$UT.TG3 * scaleFactorTG3

all$MT.TG2A <- all$MT.TG2A * scaleFactorTG2A
all$RT.TG2A <- all$RT.TG2A * scaleFactorTG2A
all$UT.TG2A <- all$UT.TG2A * scaleFactorTG2A

all$MT.TG2B <- all$MT.TG2B * scaleFactorTG2B
all$RT.TG2B <- all$RT.TG2B * scaleFactorTG2B
all$UT.TG2B <- all$UT.TG2B * scaleFactorTG2B

cat("------------------------END TO END STATS-----------------------")

cat("Average and Std Dev End to End Runtime for Test Group 1:\n")
mean(all$E2E.TG1)
sd(all$E2E.TG1)

cat("TTest between test groups 2a and 3:\n")
t.test(all$E2E.TG3, all$E2E.TG2A)

cat("Ttest between test groups 2b and 3:\n")
t.test(all$E2E.TG3, all$E2E.TG2B)

cat("Ttest between test groups 2a and 2b:\n")
t.test(all$E2E.TG2A, all$E2E.TG2B)


x <- data.frame(all$E2E.TG1, all$E2E.TG2A, all$E2E.TG2B,all$E2E.TG3)
names(x) = c("Unpacked Tar Ball Workflow", "Original SquashFS Workflow (high level SquashFuse)", "Original SquashfS Workflow (low level SquashFuse)", "Proposed SquashFS Workflow")

df <- melt(x)
ggplot(df, aes(x=value, fill=variable)) + geom_density(alpha=0.25) + labs(x="Run Time (s)", x = "Density", colour = "Charliecloud container run workflows", title="Density of Run Times for Charliecloud Container Run Workflows") 

ggplot(df, aes(x=variable, y=value, fill=variable)) + geom_boxplot() + labs(x="Charliecloud container run workflows", y="Run Time (s)", title= "Distribution of Run Times for Charliecloud Container Run Workflows") + scale_x_discrete(labels=abbreviate)

cat("\n\n\n\n")
cat("-------- MOUNT TIME STATS-----------------------------------------")

cat("TTest between test groups 2a and 3:\n")
t.test(all$MT.TG3, all$MT.TG2A)

cat("Ttest between test groups 2b and 3:\n")
t.test(all$MT.TG3, all$MT.TG2B)

cat("Ttest between test groups 2a and 2b:\n")
t.test(all$MT.TG2A, all$MT.TG2B)



x <- data.frame(all$MT.TG2A, all$MT.TG2B, all$MT.TG3)
names(x) = c("Original SquashFS Workflow (high level SquashFuse)", "Original SquashfS Workflow (low level SquashFuse)", "Proposed SquashFS Workflow")

df <- melt(x)
ggplot(df, aes(x=value, fill=variable)) + geom_density(alpha=0.25) + labs(x="Run Time (s)", x = "Density", colour = "Charliecloud container run workflows", title="Density of Run Times for Charliecloud Container Image Mounting")

ggplot(df, aes(x=variable, y=value, fill=variable)) + geom_boxplot() + labs(x="Charliecloud container run workflows", y="Run Time (s)", title= "Distribution of Run Times for Charliecloud SquashFS Mounting") + scale_x_discrete(labels=abbreviate) 

cat("\n\n\n\n")
cat("-------- RUN TIME STATS-----------------------------------------")

cat("TTest between test groups 2a and 3:\n")
t.test(all$RT.TG3, all$RT.TG2A)

cat("Ttest between test groups 2b and 3:\n")
t.test(all$RT.TG3, all$RT.TG2B)

cat("Ttest between test groups 2a and 2b:\n")
t.test(all$RT.TG2A, all$RT.TG2B)




x <- data.frame(all$RT.TG2A, all$RT.TG2B, all$RT.TG3)
names(x) = c("Original SquashFS Workflow (high level SquashFuse)", "Original SquashfS Workflow (low level SquashFuse)", "Proposed SquashFS Workflow")


df <- melt(x)
ggplot(df, aes(x=value, fill=variable)) + geom_density(alpha=0.25) + labs(x="Run Time (s)", x = "Density", colour = "Charliecloud container run workflows", title="Density of Run Times for Charliecloud Container Image Execution") 

ggplot(df, aes(x=variable, y=value, fill=variable)) + geom_boxplot() + labs(x="Charliecloud container run workflows", y="Run Time (s)", title= "Distribution of Run Times for Charliecloud SquashFS Container Execution") + scale_x_discrete(labels=abbreviate)

cat("\n\n\n\n")
cat("-------- UNMOUNT TIME STATS-----------------------------------------")

cat("TTest between test groups 2a and 3:\n")
t.test(all$UT.TG3, all$UT.TG2A)

cat("Ttest between test groups 2b and 3:\n")
t.test(all$UT.TG3, all$UT.TG2B)

cat("Ttest between test groups 2a and 2b:\n")
t.test(all$UT.TG2A, all$UT.TG2B)



names(x) = c( "Original SquashFS Workflow (high level SquashFuse)", "Original SquashfS Workflow (low level SquashFuse)", "Proposed SquashFS Workflow")

df <- melt(x)
ggplot(df, aes(x=value, fill=variable)) + geom_density(alpha=0.25) + labs(x="Run Time (s)", x = "Density", colour = "Charliecloud container run workflows", title="Density of Run Times for Charliecloud Container Image Unmounting") 

ggplot(df, aes(x=variable, y=value, fill=variable)) + geom_boxplot() + labs(x="Charliecloud container run workflows", y="Run Time (s)", title= "Distribution of Run Times for Charliecloud SquashFS Unmounting") + scale_x_discrete(labels=abbreviate)









df <- data.frame(colSums(select(all, -E2E.TG2A.Sum, -E2E.TG2B.Sum, -E2E.TG3.Sum )))
df <- cbind(df, rownames(df))
rownames(df) <- NULL
names(df) <- c("value","id")
df$id <- gsub("\\.", "_", df$id)
df <- cbind(df$value, colsplit(type.convert(df$id), '_', c("time", "group")))
names(df) <-c("value","time","group")
df <- df %>% spread(time, value)

s.MT <- c(0,0,0,0)
df <- cbind(df, s.MT)

df <- df %>% select(group, s.MT, MT, RT, UT, E2E) %>% mutate(s.RT = MT) %>% mutate(RT = s.RT + RT) %>% mutate(s.UT = RT) %>% mutate(UT = s.UT + UT) %>% select(group, s.MT, MT, s.RT, RT, s.UT, UT, E2E)
df <- df %>% gather(phase, start, -group) %>% mutate(end=start) 
df$phase <- gsub("s.","" , df$phase)

broken <- merge(x = df, y = df, by=c("group","phase"), all = TRUE) %>% select(group, phase, start.x, end.y) %>% where(start.x != end.y)
e2e <- merge(x = df, y = df, by=c("group","phase"), all = TRUE) %>% select(group, phase, start.x, end.y) %>% where(phase=="E2E")
e2e$group = c("TG1-Full", "TG2A-Full", "TG2B-Full", "TG3-Full")

broken$phase <- revalue(broken$phase, c("MT" = "SquashFS Mount", "RT" = "Container Run", "UT"="SquashFS Unmount"))
names(broken) = c("Workflow","Phase","Duration","end")
timelineG(df=broken, start="Duration", end="end", names="Workflow", phase="Phase") 
