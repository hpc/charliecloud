################### LIBRARIES #####################################
library(dplyr)
library(tidyr)

#################### Helpers######################################

dict <- read.csv("ex01-files.csv")
dict <- select(dict, Bytes)

files <- dir(path="~/charliecloud/test-overhead/", pattern="ex01-[1-5]")

read <- function(x){
    
    df <- read.csv(x)
    ID <- rep(strsplit(x,"-")[[1]][2], length(df[,1]))
    return(cbind(ID, select(df,-ID)))
}

dfs <- lapply(files,read)

all <- data.frame(dfs[1])
for (i in 2:length(dfs)){
    all <- rbind(all, data.frame(dfs[i]))
}

all <- all %>% mutate(size=dict[ID,])


# Plot End to End Times Raw
all <- all %>%
    mutate(e2e.sfsh = E_SFSH-S_SFSH) %>%
    mutate(e2e.sfsl = E_SFSL-S_SFSL) %>%
    mutate(e2e.psfsh = E_PSFSH-S_PSFSH) %>%
    select(e2e.sfsh, e2e.sfsl, e2e.psfsh, size)

all %>% gather(key,value,-size) %>%
    group_by(size,key) %>%
    summarize(meantime= mean(value)) %>%
    ggplot(aes(x=size,y=meantime,color=key)) + geom_point() + geom_smooth()

