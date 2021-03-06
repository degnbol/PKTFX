#!/usr/bin/env Rscript
# purpose of this is to assign mode to the TFs that did not have GO terms that could do it.
# these modes are therefore estimates, but we need to assign something, so that their outgoing edges can be signed
# mode inferred from datasets with mode annotation for edges (yeastract) combined with the belief in the edge (based on edge p-val)

# functions

flatten = function(x) as.vector(as.matrix(x))

setwd("~/cwd/data/network")

TFs = read.table("TF.tsv", sep="\t", header=T, stringsAsFactors=F)
V = flatten(read.table("V_protein.txt"))
edges = read.table("TF_priors/TF_edges.tsv", sep="\t", header=T, quote="", stringsAsFactors=F)
# fall back on perturbation data to find expression mode
perturbation = as.matrix(read.table("../perturbation/logFC_inner_raw.csv", sep=",", row.names=1, header=T, quote="", check.names=F, stringsAsFactors=F))

# assign each TF as either activator or repressor sign by using the mode of regulation most supported in the data
dominant_sign = function(edges) {
    signs = rep(NA, nrow(edges))
    for (TF in unique(edges$TF)) {
        activation = edges$Mode[edges$TF == TF] == "activator"
        inhibition = edges$Mode[edges$TF == TF] == "inhibitor"
        chisq_activation = -2*sum(log(edges$Pval[activation]))
        chisq_inhibition = -2*sum(log(edges$Pval[inhibition]))
        pval_activation = pchisq(chisq_activation, df=2*sum(activation), lower.tail=F, log.p=T)
        pval_inhibition = pchisq(chisq_inhibition, df=2*sum(inhibition), lower.tail=F, log.p=T)
        
        if (pval_activation < pval_inhibition) {signs[edges$TF == TF] = "+"}
        if (pval_activation > pval_inhibition) {signs[edges$TF == TF] = "-"}
    }
    signs
}

edges$sign = dominant_sign(edges)

sum(edges$sign == "+", na.rm=T)
sum(edges$sign == "-", na.rm=T)


agree = (edges$sign == "+" & edges$Mode == "activator") | (edges$sign == "-" & edges$Mode == "inhibitor")
sum(agree)
sum(!agree & edges$Mode != "")
# maybe this is attributed to cofactors and other regulators that flip the sign of regulation

# most have been given a sign now which is great
sum(is.na(edges$sign))
sum(!is.na(edges$sign))

# provide sign from perturbation data where a TF is KOed
for(i in 1:nrow(edges)) {if (is.na(edges$sign[i])) {
    logFC = perturbation[rownames(perturbation)==edges$Target[i], colnames(perturbation)==edges$TF[i]]
    if (length(logFC) == 1) {
        if (logFC > 0) {edges$Mode[i] = "inhibitor"}
        if (logFC < 0) {edges$Mode[i] = "activator"}
    }
    else if (length(logFC) > 1) {cat("warning\n")}
}}

edges$sign[is.na(edges$sign)] = dominant_sign(edges)[is.na(edges$sign)]
unresolved = unique(edges$TF[is.na(edges$sign)])
length(unresolved) # 18 TFs that are unsigned

TF_signs = edges$sign[match(TFs$TF, edges$TF)]

# get the sign of expression correlation between an unresolved TF and its targets
for (TF in unresolved) {if (TF %in% rownames(perturbation)) {
    targets = edges$Target[edges$TF == TF]
    targets = targets[targets %in% rownames(perturbation)]
    
    source_measurements = rep(perturbation[TF,], length(targets))
    # all measurements will be zero if the source is actually never KOed. 
    # This check serves kinda the same function as the na check, but it is to avoid a warning message.
    if(any(source_measurements != 0)) {
        corr = as.vector(cor(source_measurements, matrix(perturbation[targets,], byrow=T)))
        if (!is.na(corr)) {  # will be NA if all values are zero for TF, which is the case for e.g. MATA1
            if (corr < 0) {TF_signs[TFs$TF == TF] = "-"}
            if (corr > 0) {TF_signs[TFs$TF == TF] = "+"}
        }
    }
}}


TFs$Mode[TF_signs == "+" & !is.na(TF_signs) & TFs$Mode == ""] = "activator"
TFs$Mode[TF_signs == "-" & !is.na(TF_signs) & TFs$Mode == ""] = "repressor"


# manually looking up the only remaining TFs:
stopifnot(TFs$TF[TFs$Mode == ""] == c("MAL63", "MATA1", "YER108C"))
# SGD says MATA1 represses genes, and YER108C is a point mutated copy of YER109C (FLO8) which is an activator, MAL63 is positive regulation
TFs$Mode[TFs$TF == "MATA1"] = "repressor"
TFs$Mode[TFs$TF == "YER108C"] = "activator"
TFs$Mode[TFs$TF == "MAL63"] = "activator"
stopifnot(all(TFs$Mode != ""))


write.table(TFs, "TF_mode.tsv", sep="\t", quote=F, row.names=F)
