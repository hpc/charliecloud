

e2e <- read.csv('ex02-E2E.csv')

print("Average End to End Runtime for Test Group 1:")
mean(e2e$E2E.TG1)

print("Average End to End Runtime for Test Group 2:")
mean(e2e$E2E.TG2)

print("Average End to End Runtime for Test Group 3:")
mean(e2e$E2E.TG3)


print("TTest between test groups 2 and 3")
t.test(e2e$E2E.TG3, e2e$E2E.TG2)
