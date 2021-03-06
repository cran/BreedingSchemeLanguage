#'Plot the results
#'
#'@param sEnv the environment that BSL functions operate in. Default is "simEnv" so use that to avoid specifying when calling functions
#'@param ymax the maximum value of y-axis (default: the maximun value in the data)
#'@param add if TRUE a new result will be added to an existing plot, using data loaded from addDataFileName. if FALSE a new plot will be drawn (default)
#'@param addDataFileName if not NULL, the name to save the summarized data for the next simulation, like "plot1_1". A path can be specified, like "simDirectory/plot1_1" (in which case "simDirectory" must exist). Default: NULL
#'@param popID list of vectors of the population IDs you want plotted
#'@param suppress if TRUE, this call is just to assemble the data to be plotted in a later call to plotData (default: FALSE)
#'
#'@seealso \code{\link{defineSpecies}} for an example
#'
#'@return A matrix with the plot data
#'
#'@export
plotData <- function(sEnv=NULL, ymax=NULL, add=FALSE, addDataFileName=NULL, popID=NULL, suppress=F){
  if(is.null(sEnv)){
    if(exists("simEnv", .GlobalEnv)){
      sEnv <- get("simEnv", .GlobalEnv)
    } else{
      stop("No simulation environment was passed")
    }
  } 
  plotBase <- is.null(popID)
  if (plotBase) popID <- sort(unique(sEnv$sims[[1]]$genoRec$basePopID))
  nLoc <- ncol(sEnv$sims[[1]]$gValue)
  
  getMeans <- function(bsl, loc){
    if (plotBase) pID <- bsl$genoRec$basePopID
    else pID <- bsl$genoRec$popID
    return(tapply(bsl$gValue[,loc], pID, mean))
  }
  muSimByLoc <- lapply(1:nLoc, function(loc) list(muSim=t(sapply(sEnv$sims, getMeans, loc=loc)), loc=loc))
  
  if (class(popID) == "list"){
    pID <- sEnv$sims[[1]]$genoRec$popID
    popSizes <- tapply(pID, pID, length)
    modifyMSBL <- function(muSim){
      ms <- muSim$muSim
      getMeanOfPops <- function(popVec){
        cnames <- as.character(popVec)
        cnames <- intersect(cnames, colnames(ms))
        if (length(cnames) == 0) stop("Plotting popIDs that are empty")
        apply(ms, 1, function(vec) stats::weighted.mean(vec[cnames], popSizes[cnames]))
      }
      muSim$muSim <- matrix(sapply(popID, getMeanOfPops), ncol=length(popID))
      return(muSim)
    }
  } else{
    modifyMSBL <- function(muSim){
      muSim$muSim <- muSim$muSim[, as.character(popID), drop=F]
      return(muSim)
    }
  }
  muSimByLoc <- lapply(muSimByLoc, modifyMSBL)
  
  makeDF <- function(muSim){
    loc <- muSim$loc
    muSim <- muSim$muSim
    muSim <- muSim - muSim[, 1]
    g <- NULL
    group <- NULL
    size <- NULL
    nGenPlot <- length(popID)
    for(sim in 1:nrow(muSim)){
      g <- c(g, muSim[sim, ])
      group <- c(group, rep(sim, nGenPlot))
      size <- c(size, rep(1, nGenPlot))
    }
    nrp <- 0
    if (nrow(muSim) > 1){
      g <- c(g, apply(muSim, 2, mean))
      group <- c(group, rep(sEnv$nSim + 1, nGenPlot))
      size <- c(size, rep(2, nGenPlot))
      nrp <- 1
    }
    plotData <- data.frame(g=g, popID=rep(0:(nGenPlot - 1), nrow(muSim) + nrp), size=size, col=loc, group=group, scheme=1)
  }#END makeDF
  muSimByLoc <- lapply(muSimByLoc, makeDF)
  
  plotData <- NULL
  maxGroup <- 0
  for (loc in 1:nLoc){
    toAdd <- muSimByLoc[[loc]]
    toAdd$group <- toAdd$group + maxGroup
    maxGroup <- max(toAdd$group)
    plotData <- rbind(plotData, toAdd)
  }
  
  totCost <- sEnv$totalCost
  if (add){
    prevData <- try(suppressWarnings(readRDS(file=paste(addDataFileName, ".rds", sep=""))), silent=T)
    if (class(prevData) != "try-error"){
    totCost <- c(prevData$totCost, totCost)
    prevData <- prevData$plotData
    plotData$scheme <- plotData$scheme + max(prevData$scheme)
    plotData$group <- plotData$group + max(prevData$group)
    plotData <- rbind(plotData, prevData)
    }
  }
  if (!is.null(addDataFileName)) saveRDS(list(plotData=plotData, totCost=totCost), file=paste(addDataFileName, ".rds", sep=""))
  
  plotData$group <- as.factor(plotData$group)
  plotData$col <- as.factor(plotData$col)
  plotData$size <- as.factor(plotData$size)
  plotData$scheme <- as.factor(plotData$scheme)
  
  mapping <- ggplot2::aes_string(x="popID", y="g", group="group")
  if (length(unique(plotData$col)) > 1) mapping <- utils::modifyList(mapping, ggplot2::aes_string(colour="col"))
  if (length(unique(plotData$size)) > 1) mapping <- utils::modifyList(mapping, ggplot2::aes_string(size="size"))
  if (length(unique(plotData$scheme)) > 1) mapping <- utils::modifyList(mapping, ggplot2::aes_string(linetype="scheme"))
  p <- ggplot2::ggplot(data=plotData, mapping)
  p <- p + ggplot2::geom_line()
  if (is.null(ymax)) {
    p <- p + ggplot2::ylim(min(plotData$g), max(plotData$g))
  }
  else {
    p <- p + ggplot2::ylim(min(plotData$g), ymax)
  }
  xLabel <- ifelse(plotBase, "Cycle", "Population")
  p <- p + ggplot2::labs(title="", x=xLabel, y="Genetic improvement")
  
  if (length(unique(plotData$col)) > 1){
    cbPalette <- c("#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442", "#0072B2", "#D55E00", "#CC79A7")
    p <- p + ggplot2::scale_colour_manual(values=cbPalette)
    p <- p + ggplot2::guides(col=ggplot2::guide_legend("Locs"))
  } 
  if (length(unique(plotData$size)) > 1){
    p <- p + ggplot2::scale_size_manual(name="", values=c(0.3, 2), labels=c("Repl", "Mean"))
    p <- p + ggplot2::guides(size=ggplot2::guide_legend("Lines"))
  } 
  if (length(unique(plotData$scheme)) > 1){
    p <- p + ggplot2::guides(linetype=ggplot2::guide_legend("Scheme"))
  }
  if (!is.null(totCost)){
    p <- p + ggplot2::ggtitle(paste("Cost of scheme", ifelse(length(totCost) > 1, "s", ""), ": ", paste(round(totCost), collapse=", "), sep=""))
  }
  if (!suppress) print(p)
}
