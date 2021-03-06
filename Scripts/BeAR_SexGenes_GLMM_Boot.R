## Find predictors of sex DE

# load data and select an Fdr threshold 
load(file="./Output/BaseStats_out.RData")
sexdedata<-as.data.frame(apply(fit2$Fdr[,6:10],1, function(x){any(x<0.01)}))
names(sexdedata)<-c("sexDE")
# add OGS2 information
OGS2.0<- read.csv("./Input/NVIT_OGS2_goodannotcomplete.csv")

sex_data<-merge(sexdedata,OGS2.0[,c("geneID","LinkageCluster","recombrate","cM","Kb","ODB6_OG_ID","adult_female_meth_status","quality7","isoforms","IntMatch","quality2","ratio")], by.x="row.names", by.y="geneID", all.x=T)
sex_data$LinkageCluster<-as.factor(sex_data$LinkageCluster)
sex_data$Chromosome<-as.factor(substr(sex_data$LinkageCluster, 1, 1))
sex_data$KbCM<-sex_data$Kb/sex_data$cM
names(sex_data)<-c("geneID","sexDE","LinkageCluster","recombrate","cM","Kb","ODB6_OG_ID","Methylated", "Paralog", "Isoforms","IntMatch","quality2", "AA_evol_ratio","Chromosome","KbcM")

# Which factors have the most missing values?
apply(sex_data, 2, function(x){sum(is.na(x))})

# add number of genes on each cluster
sex_data<-merge(sex_data, as.data.frame(table(sex_data$LinkageCluster)), by.x="LinkageCluster", by.y="Var1", all.x=T)
names(sex_data)[ncol(sex_data)]<-"Ngenes"

# Select only models with strong expression support (important when considering isoforms)
sex_data<-droplevels(sex_data[which(sex_data$quality2=="Express:Strong"),])

# Select only models with orthology/paralogy assignments (genes with no ortholog/paralog have too few isoforms)
# mosaicplot(Paralog~sexDE+(Isoforms>1), data=sex_data)
sex_data<-droplevels(sex_data[which(sex_data$Paralog!="None"),])

# How much of OGS2 is present in the final model?
table(OGS2.0$geneID%in%sex_data$geneID)
prop.table(table(OGS2.0$geneID%in%sex_data$geneID))
# After exclusion of entries with NAs?
sex_data<-droplevels(na.omit(sex_data))
table(OGS2.0$geneID%in%sex_data$geneID)
prop.table(table(OGS2.0$geneID%in%sex_data$geneID))


# Fit maximal model
library(lme4)
binomfull<-glmer(sexDE~Paralog-1+Methylated+log10(Ngenes)+log10(recombrate+0.000001)+log10(IntMatch+1)+log10(AA_evol_ratio)+(1|LinkageCluster)+(1|ODB6_OG_ID), family="binomial", data=sex_data)

# previous AICc based data-exploration supports retaining OG. Support for Linkage cluster is low if ngenes and recombrate are present

# Calculate bootstrap based parameter estimates
# NOTE: bootMer cannot handle NAs, so remove those before fitting main model (data=na.omit(dataset))

# Parameter sampling function: sample all fixed effect estimates, variance estimates for random effects and sigma (returns error for sigma, so put it last to avoid loop skipping)
mySumm <- function(.) {
  c(beta=fixef(.),sig01=unlist(VarCorr(.)))
}
# Resample model (specify number of replicates and verbosity)
boo01<-bootMer(binomfull, mySumm, nsim=1000)

# # View model
# boo01

# Create list to store confidence intervals with different methods
bootCIs<-list(normal=as.data.frame(matrix(nrow=length(boo01$t0), ncol=3)),
              basic=as.data.frame(matrix(nrow=length(boo01$t0), ncol=5))
)
# Rename parameters
bootCIs<-lapply(bootCIs, function(x){
  row.names(x)<-names(boo01$t0)
  x
})
# Rename variables
names(bootCIs$normal)<-c("alpha","lowerCI","upperCI")
names(bootCIs$basic)<-c("alpha","lowerEND","upperEND","lowerCI","upperCI")

# Calculate confidence intervals for each factor with normal and basic method (when error skips line, must skip before)
library(boot)
for (i in 1:length(boo01$t0)){
  a<-boot.ci(boo01, index=i, conf=0.95, type=c("norm","basic"))
  bootCIs[["normal"]][i,]<-a[["normal"]]
  bootCIs[["basic"]][i,]<-a[["basic"]]
}
# and plot resampled parameter densities (title not printing correctly)
pdf(paste(c("./Graphics/",format(Sys.time(), "%y_%m_%d"),"_SexGenes_GLMM_Boot1000_estimates.pdf"), collapse=""), paper="a4", onefile=T)
for (i in 1:length(boo01$t0)){
  print(plot(boo01, index=i),
        title(main=names(boo01$t0[i])))
}
dev.off()

# Save results to workspace
save.image(paste(c("./Output/",format(Sys.time(), "%y_%m_%d"),"_SexGenes_GLMM_Boot1000_results.RData"), collapse=""))


## Caveats and model criticism
# 1) Maximal model does not estimate individual linkage groups (will do so if they are a significant variance component in the final model)
# 2) Model relies on OGS2.0 annotation of isoforms, increasing false positive in case of dev/sex specific splicing and restricts the dataset to strong expression support models only (unequal representation in isoforms between different classes of evidence)
# 3) Methylation is based on adult females and is also highly correlated with mean gene expression values and expression support 
# 4) Main sources of NAs result from AA evolution, Methylation and Expression support
# 5) No test for overdispersion/absolute model fit implemented in this version, will run it on minimized model