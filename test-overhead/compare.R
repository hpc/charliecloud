

e2e <- read.csv('ex02-E2E.csv')
broken <- read.csv('ex02.csv')

cat("Average and Std Dev End to End Runtime for Test Group 1:\n")
mean(e2e$E2E.TG1)
sd(e2e$E2E.TG1)

cat("Average and Std Dev End to End Runtime for Test Group 2:\n")
mean(e2e$E2E.TG2)
sd(e2e$E2E.TG2)

cat("Average and Std Dev End to End Runtime for Test Group 3:\n")
mean(e2e$E2E.TG3)
sd(e2e$E2E.TG3)

cat("TTest between test groups 2 and 3:\n")
t.test(e2e$E2E.TG3, e2e$E2E.TG2)


cat("Average Mount Time for Test group 2:\n")
mean(broken$MT.TG2)
sd(broken$MT.TG2)

cat("Average Mount time for Test group 3:\n")
mean(broken$MT.TG3)
sd(broken$MT.TG3)

cat("Ttest between mount times for test groups 2 and 3:\n")
t.test(broken$MT.TG3, broken$MT.TG2)

cat("Average Run Time for Test group 2:\n")
mean(broken$RT.TG2)
sd(broken$RT.TG2)

cat("Average Run time for Test group 3:\n")
mean(broken$RT.TG3)
sd(broken$RT.TG3)

cat("Ttest between run times for test groups 2 and 3:\n")
t.test(broken$RT.TG3, broken$RT.TG2)


cat("Average UnMount Time for Test group 2:\n")
mean(broken$UT.TG2)
sd(broken$UT.TG2)

cat("Average Unmount time for Test group 3:\n")
mean(broken$UT.TG3)
sd(broken$UT.TG3)

cat("Ttest between unmount times for test groups 2 and 3:\n")
t.test(broken$UT.TG3, broken$UT.TG2)



