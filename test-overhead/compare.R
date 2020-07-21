library(dplyr)

e2e <- read.csv('ex02-E2E.csv')
broken <- read.csv('ex02.csv')



broken <-broken %>% mutate(E2E.TG2.Sum = MT.TG2 + RT.TG2 + UT.TG2) 
broken <-broken %>% mutate(E2E.TG3.Sum = MT.TG3 + RT.TG3 + UT.TG3) 
all <- cbind(select(broken, -ID), select(e2e, -ID))
scaleFactorTG2 <- mean(all$E2E.TG2) / mean(all$E2E.TG2.Sum)

scaleFactorTG3 <- mean(all$E2E.TG3) / mean(all$E2E.TG3.Sum)
all$MT.TG3 <- all$MT.TG3 * scaleFactorTG3
all$RT.TG3 <- all$RT.TG3 * scaleFactorTG3
all$UT.TG3 <- all$UT.TG3 * scaleFactorTG3

all$MT.TG2 <- all$MT.TG2 * scaleFactorTG2
all$RT.TG2 <- all$RT.TG2 * scaleFactorTG2
all$UT.TG2 <- all$UT.TG2 * scaleFactorTG2



cat("Average and Std Dev End to End Runtime for Test Group 1:\n")
mean(all$E2E.TG1)
sd(all$E2E.TG1)

cat("Average and Std Dev End to End Runtime for Test Group 2:\n")
mean(all$E2E.TG2)
sd(all$E2E.TG2)

cat("Average and Std Dev End to End Runtime for Test Group 3:\n")
mean(all$E2E.TG3)
sd(all$E2E.TG3)

cat("TTest between test groups 2 and 3:\n")
t.test(all$E2E.TG3, all$E2E.TG2)


cat("Average Mount Time for Test group 2:\n")
mean(all$MT.TG2)
sd(all$MT.TG2)

cat("Average Mount time for Test group 3:\n")
mean(all$MT.TG3)
sd(all$MT.TG3)

cat("Ttest between mount times for test groups 2 and 3:\n")
t.test(all$MT.TG3, all$MT.TG2)

cat("Average Run Time for Test group 2:\n")
mean(all$RT.TG2)
sd(all$RT.TG2)

cat("Average Run time for Test group 3:\n")
mean(all$RT.TG3)
sd(all$RT.TG3)

cat("Ttest between run times for test groups 2 and 3:\n")
t.test(all$RT.TG3, all$RT.TG2)


cat("Average UnMount Time for Test group 2:\n")
mean(all$UT.TG2)
sd(all$UT.TG2)

cat("Average Unmount time for Test group 3:\n")
mean(all$UT.TG3)
sd(all$UT.TG3)

cat("Ttest between unmount times for test groups 2 and 3:\n")
t.test(all$UT.TG3, all$UT.TG2)



