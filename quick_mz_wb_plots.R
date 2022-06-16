# Script to plot mozart water balance
# Hupsel

rm(list =ls())
# Libraries
library(ggplot2)
library(lubridate)
library(dplyr)
library(reshape2)
library(tidyr)

#Update to common bach dir
maindir <- "C:/Git/bach/"
file = file.path(maindir, "data/lhm-daily/LHM41_dagsom/work/mozart/lswwaterbalans.out")
lsw = 151358

#Read and format data
df <- read.delim(file, skip =2, header = F, sep = " ")
names <- read.delim(file, skip =1,sep = " ", header =F)[1,]
colnames(df) <- names[-which(is.na(names[1,]))]
df$TIMEEND <- ymd(df$TIMEEND)
df$TIMESTART<- ymd(df$TIMESTART)
df <- df[,-36]
rm(names)

#remove all data except lsw of interst
lswdf <- df[df$LSWNR==lsw,]
lswdf <- lswdf[-which(is.na(lswdf$LSWNR)),]

# Plot individual timeseries for all variables
pdf(paste(maindir, "plots/mzwaterbalance/mz_ts_hupsel_all_variables.pdf", sep = ""),
    width = 12, height = 8)
for(i in 6:ncol(lswdf)){
  
  if(colnames(lswdf)[i] == "PRECIP"|colnames(lswdf)[i] == "EVAPORATION"){
    plot(lswdf$TIMESTART, lswdf[,i], type = "h", col = "blue", main = paste("LSW Water Balance:" ,colnames(lswdf)[i]),
         ylab= expression(Flux ~ m^3/d), xlab = "Date")
  }else{
    plot(lswdf$TIMESTART, lswdf[,i], type = "l", col = "blue", main = paste("LSW Water Balance:" ,colnames(lswdf)[i]),
         ylab= expression(Flux ~ m^3/d), xlab = "Date")
  }
  abline(h = pretty(range(lswdf[,i])), col = "lightgrey", lty =5)
  abline(v = ymd(paste(unique(format(lswdf$TIMESTART, "%Y-%m")), "-01", sep = "") ), col = "lightgrey", lty =5)
}
dev.off()


# plot totals for the month and flux

lswdf$month <- month(lswdf$TIMESTART)

newdf <- data.frame(Month = unique(lswdf$month))
for(i in 6:35){
  newdf[,i-4] <- tapply(lswdf[,i] ,lswdf$month,FUN =sum ) # sum by month
  names(newdf)[i-4] <- colnames(lswdf)[i] # keep naming consistent
}

# plot only variables with non 0 values
subsetdf <- newdf[,which(colSums(newdf) != 0)]
plotdata <- melt(subsetdf, id = "Month", variable.name = "variable", value.name = "flux")
plotdata$Month <- factor(plotdata$Month, ordered  = unique(lswdf$month), levels = unique(lswdf$month))

plotdata <- data.frame(Month = plotdata$Month,
                       Flux = plotdata$flux,
                       variable = plotdata$variable)

yexpression <- expression(Flux ~ m^3/month)
plt <- ggplot(plotdata, aes(x = Month, y= Flux, fill = variable))+
  geom_bar(position = "stack", stat = "identity")+
  ylab(yexpression)+
  xlab("Month")+
  ggtitle("Hupsel Water Balance - Mozart")+
  labs(caption = "Note: positive = inflow to LSW, negative = outflow from LSW")
  
  

ggsave(file.path(maindir,"plots/mzwaterbalance/subset_variables_by_month.pdf"), width =12, height =8)
dev.off()
