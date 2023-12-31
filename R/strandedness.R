#' Identify strandMode
#'
#' Identify \code{strandMode} (strandedness) in RNA-seq data samples based on
#' the proportion of reads aligning to the same or opposite strand as
#' transcripts in the annotations.
#'
#' @param bfl A \code{BamFile} or \code{BamFileList} object, or a character
#' string vector of BAM filenames.
#'
#' @param txdb A character string of a \code{TxDb} package, or a \code{TxDb}
#' object, with gene and transcript annotations. For accurate calculations, it
#' is important that the version of these annotations matches the version of
#' the annotations used to inform the alignment of spliced reads, by the
#' short-read aligner software that generated the input BAM files.
#'
#' @param singleEnd (Default FALSE) Logical value indicating if reads are
#' single (\code{TRUE}) or paired-end (\code{FALSE}).
#'
#' @param stdChrom (Default TRUE) Logical value indicating whether only
#' alignments in the 'standard chromosomes' should be used. Consult the help
#' page of the function \code{\link[GenomeInfoDb]{keepStandardChromosomes}}
#' from the package \code{GenomeInfoDb} for further
#' information.
#'
#' @param yieldSize (Default 5e5) Number of records to read from each input
#' BAM file.
#'
#' @param verbose (Default TRUE) Logical value indicating if progress should be
#' reported through the execution of the code.
#'
#' @param BPPARAM An object of a \linkS4class{BiocParallelParam} subclass
#' to configure the parallel execution of the code. By default, a
#' \linkS4class{SerialParam} object is used, which does not use any
#' parallelization, with the flag \code{progress=TRUE} to show progress
#' through the calculations.
#'
#' @return A \link[base:list]{list} object with two elements:
#' \itemize{
#'   \item "strandMode": the \code{strandMode} of the sample(s) following
#'         \code{\link[GenomicAlignments:GAlignmentPairs-class]{GAlignmentPairs}}
#'         class definition. If all samples have the same \code{strandMode},
#'         the length of the vector is 1. It can take values: \code{NA}
#'         (library is not strand-specific), 1 (strand of pair is strand of 
#'         its first alignment), 2 (strand of pair is strand of its second 
#'         alignment) or "ambiguous" (additional category used here for 
#'         samples not fitting any of the three previous categories).
#'         See "Details" section below to know the classification criteria,
#'         as well as to how interpret results for single-end data.
#'   \item "Strandedness": data.frame with one row per sample and 3 columns.
#'         "strandMode1": proportion of alignments aligned to the same
#'         strand than a transcript according
#'         to the strand of its first alignment. "strandMode2": proportion
#'         of alignments aligned to the same strand than a transcript according
#'         to the strand of its second alignment. "ambiguous": alignments
#'         aligned to regions with transcripts in both strands.
#' }
#' 
#' @details
#' If the value in the "strandMode1" column is > 0.90, \code{strandMode} is set
#' to 1L. If "strandMode2" column is > 0.90, \code{strandMode} is set to 2L. If
#' "strandMode1" and "strandMode2" are comprised between 0.40 and 0.60,
#' \code{strandMode} is set to \code{NA} If none of the three previous criteria
#' are met, \code{strandMode} is set to "ambiguous". This criteria can be
#' conservative in some cases (e.g. when there is genomic DNA contamination), 
#' for this reason we recommend to check the data.frame with strandedness 
#' values.
#'  
#' In case of single-end data, the same criteria are used, but the
#' interpretation of \code{strandMode = 1L} and \code{strandMode = 2L}
#' changes: when \code{strandMode = 1L} the strand of the read is concordant
#' with the reference annotations, when \code{strandMode = 2L} the correct 
#' read strand is the opposite to the one of the read.
#' 
#' A subset of 200,000 alignments overlapping gene annotations are used to
#' compute strandedness.
#' 
#' 
#' @examples
#' library(gDNAinRNAseqData)
#' 
#' library(TxDb.Hsapiens.UCSC.hg38.knownGene)
#' txdb <- TxDb.Hsapiens.UCSC.hg38.knownGene
#' 
#' # Retrieving BAM files
#' bamfiles <- LiYu22subsetBAMfiles()
#' bamfiles <- bamfiles[c(1,7)] # using a subset of samples
#' 
#' strandM <- identifyStrandMode(bamfiles, txdb, singleEnd=FALSE)
#' strandM$strandMode
#' head(strandM$Strandedness)
#'
#'
#' @importFrom BiocGenerics basename path
#' @importFrom S4Vectors mcols mcols<-
#' @importFrom Rsamtools scanBamFlag ScanBamParam
#' @importFrom AnnotationDbi select
#' @importFrom GenomicFeatures exonsBy
#' @importFrom GenomeInfoDb keepStandardChromosomes genome
#' @importFrom BiocParallel SerialParam bplapply bpnworkers
#' @export
#' @rdname strandedness

identifyStrandMode <- function(bfl, txdb, singleEnd=TRUE, stdChrom=TRUE,
                                yieldSize=1000000L, verbose=TRUE,
                                BPPARAM=SerialParam(progressbar=verbose)) {
    
    yieldSize <- .checkYieldSize(yieldSize)
    bfl <- .checkBamFileListArgs(bfl, singleEnd, fragments=FALSE, yieldSize)
    .checkOtherArgs(singleEnd, stdChrom)
    
    if (is.character(txdb))
        txdb <- .loadAnnotationPackageObject(txdb, "txdb", "TxDb",
                                            verbose=verbose)
    if (verbose)
        message(sprintf("Fetching annotations for %s", genome(txdb)[1]))
    
    ## fetch transcript annotations
    exbytx <- exonsBy(txdb, by="tx")
    if (stdChrom) {
        exbytx <- keepStandardChromosomes(exbytx, pruning.mode="fine")
        exbytx <- exbytx[lengths(exbytx) > 0]
    }
    sbflags <- scanBamFlag(isUnmappedQuery=FALSE,
                            isProperPair=!singleEnd,
                            isSecondaryAlignment=FALSE,
                            isDuplicate=FALSE,
                            isNotPassingQualityControls=FALSE)
    param <- ScanBamParam(flag=sbflags)
    
    if (verbose)
        message("Start processing BAM file(s)")
    
    # strandedness by strandMode
    strbysm <- NULL
    if (length(bfl) > 1 && bpnworkers(BPPARAM) > 1) {
        verbose <- FALSE
        strbysm <- bplapply(bfl, .strness_oneBAM, tx=exbytx, stdChrom=stdChrom,
                            singleEnd=singleEnd, strandMode=1L, param=param,
                            verbose=verbose, BPPARAM=BPPARAM)
    } else
        strbysm <- lapply(bfl, .strness_oneBAM, tx=exbytx, stdChrom=stdChrom,
                            singleEnd=singleEnd, strandMode=1L, param=param,
                            verbose=verbose)
    
    names(strbysm) <- gsub(pattern = ".bam", "", names(strbysm), fixed = TRUE)
    strbysm <- do.call("rbind", strbysm)
    .checkMinNaln(strbysm) # warning if n. align < 1e+05
    sm <- .decideStrandMode(strbysm)
    
    strbysmtype <- list("strandMode" = sm, "Strandedness" = strbysm)
    strbysmtype
}

## Private function to get strandedness from BAM file
#
#' @importFrom BiocGenerics basename path
#' @importFrom Rsamtools isOpen yieldSize
#' @importFrom GenomicAlignments readGAlignments readGAlignmentPairs
#' @importFrom GenomeInfoDb keepStandardChromosomes
.strness_oneBAM <- function(bf, tx, stdChrom, singleEnd, strandMode=1L,
                            param, verbose) {
    if (isOpen(bf))
        close(bf)
    
    if (verbose)
        message(sprintf("Computing strandedness from %s", basename(path(bf))))
    
    i <- 0L
    gal <- NULL
    naln <- 0L
    nalnbystr <- integer(4L)
    open(bf)
    while (naln < 2e+05 & i < 10) {
        if (singleEnd)
            gal <- readGAlignments(bf, param=param, use.names=FALSE)
        else
            gal <- readGAlignmentPairs(bf, param=param, strandMode=strandMode,
                                      use.names=FALSE)
        if (stdChrom)
            if (singleEnd)
                gal <- keepStandardChromosomes(gal, pruning.mode="coarse")
            else
                gal <- keepStandardChromosomes(gal, pruning.mode="fine")
        
        if (length(gal) == 0)
            break
        
        gal <- .matchSeqinfo(gal, tx, verbose)
        nalnbf <- .getStrandedness(gal, tx, reportAll=TRUE)
        nalnbystr <- nalnbf + nalnbystr
        naln <- nalnbystr["Nalignments"]
        i <- i + 1
    }
    on.exit(close(bf))
    
    if (i >= 10)
        warning(sprintf("Reading 10 million alignments from %s was not enough to get >= 2e+05 alignments overlapping a gene, this can affect the accuracy of the strandedness", basename(path(bf))))
    
    ## strandedness value (according to strandMode specified)
    strness <- nalnbystr["nalnst"] / naln
    
    ## strandedness value (opposite to strandMode specified)
    strnessis <- nalnbystr["nalnisst"] / naln
    
    ## proportion of alignments considered ambiguous
    strnessambig <- nalnbystr["ambig"] / naln
    
    strbysm <- c(strness, strnessis, strnessambig, naln)
    names(strbysm) <- c("strandMode1", "strandMode2", "ambig", "Nalignments")
    strbysm
}

## Private function to get strandedness value for specific strandMode
#
#' @importFrom methods is
#' @importFrom IRanges findOverlaps
#' @importFrom S4Vectors queryHits
#' @importFrom GenomicAlignments invertStrand strandMode
#' @importFrom GenomicRanges GRanges
.getStrandedness <- function(gal, tx, reportAll=FALSE) {
    
    if (reportAll & is(gal, "GAlignmentPairs")) 
        if (strandMode(gal) != 1L)
            stop("strandMode of 'gal' must be 1L when ",
                "'reportAll = TRUE'.")
    
    ## calculate overlaps between alignments and transcripts
    ovtx <- findOverlaps(GRanges(gal), tx, ignore.strand=FALSE)
    
    ## build a mask to select only 1 overlap per alignment (to avoid counting
    ## twice an alignment if it maps to > transcript)
    ovtxaln <- ovtx[!duplicated(queryHits(ovtx))]
    
    ## calculate overlaps between antisense alignments and transcripts
    ovtxis <- findOverlaps(invertStrand(GRanges(gal)), tx, ignore.strand=FALSE)
    ovtxisaln <- ovtxis[!duplicated(queryHits(ovtxis))]
    
    ## identifying ambiguous alignments (mapping to regions with transcripts in
    ## both strands)
    ambaln <- intersect(queryHits(ovtxaln), queryHits(ovtxisaln))
    
    ## number of alignments aligned to correct strand of transcripts
    nalnst <- sum(!queryHits(ovtxaln) %in% ambaln)
    
    ## number of alignments aligned to oposite strand of transcripts
    nalnisst <- sum(!queryHits(ovtxisaln) %in% ambaln)
    
    ambig <- length(ambaln)/(nalnst + nalnisst + length(ambaln))
    if (ambig > 0.10)
        warning("The proportion of alignments mapping to regions with ",
                "transcripts annotated to both strands is > 0.10, this can ",
                "cause strandedness value to be low.")
    
    if (reportAll) {
        naln <- nalnst + nalnisst + length(ambaln)
        
        c("nalnst" = nalnst, "nalnisst" = nalnisst, "ambig" = length(ambaln),
            "Nalignments" = naln)
        
    } else {
        ## strandedness value (according to strandMode specified) ignoring
        ## proportion of ambiguous alignments
        strness2 <- nalnst / (nalnst + nalnisst)
        
        strness2
    }
}

## Private function to decide strandMode based on .getStrandedness() output
.decideStrandMode <- function(strbysm) {
    
    sm <- rep("ambiguous", nrow(strbysm))
    sm[strbysm[,"strandMode1"] > 0.9] <- 1L
    sm[strbysm[,"strandMode2"] > 0.9] <- 2L
    unkn <- strbysm[,"strandMode1"] > 0.40 & strbysm[,"strandMode1"] < 0.60 &
        strbysm[,"strandMode2"] > 0.40 & strbysm[,"strandMode2"] < 0.60
    sm[unkn] <- NA
    # sm[strbysm[,"ambig"] > 0.15] <- "highAmbiguous"
    
    names(sm) <- rownames(strbysm)
    if (length(unique(sm)) == 1)
        sm <- unique(sm)
    
    if (!any(sm == "ambiguous" | is.na(sm)))
        sm <- as.integer(sm)
    
    sm
}

## Private function to issue a warning when the strandedness value is
## computed from a low number of alignments
.checkMinNaln <- function(strbysm) {
    
    lownaln <- strbysm[,"Nalignments"] < 1e+05
    
    if (any(lownaln)) {
        messlownaln <- paste("The following samples had less than 1e+05 ",
                        "alignments overlapping exonic regions, decreasing ",
                        "the accuracy of the strandedness value: %s. ")
        whlownaln <- paste(rownames(strbysm)[lownaln], collapse = ", ")
        warning(sprintf(messlownaln, whlownaln))
    }
}



#' Compute strandedness for each feature
#'
#' Compute strandedness for each feature in RNA-seq data samples based on
#' the proportion of reads aligning to the same strand as feature annotations
#' in relation to the total number of reads aligning to that feature.
#'
#' @param bfl A \code{BamFile} or \code{BamFileList} object, or a character
#' string vector of BAM filenames.
#'
#' @param features A \code{GRanges} or \code{GRangesList} object with
#' annotations of features (e.g. genes, transcripts, etc.).
#'
#' @param singleEnd (Default FALSE) Logical value indicating if reads are
#' single (\code{TRUE}) or paired-end (\code{FALSE}).
#' 
#' @param strandMode (Default 1L) Numeric vector which can take values 0, 1,
#' or 2. The strand mode is a per-object switch on
#' \code{\link[GenomicAlignments:GAlignmentPairs-class]{GAlignmentPairs}}
#' objects that controls the behavior of the strand getter. See
#' \code{\link[GenomicAlignments:GAlignmentPairs-class]{GAlignmentPairs}}
#' class for further detail. If \code{singleEnd = TRUE}, then \code{strandMode}
#' is ignored.
#'
#' @param yieldSize (Default 5e5) Field inherited from
#' \code{\link[Rsamtools]{BamFile}}. The BAM is read by chunks.
#' \code{yieldSize} represents the number of records to read for each chunk.
#' 
#' @param ambiguous (Default FALSE) Logical value indicating if reads that
#' overlap a region with features annotated to both strands should be included
#' in the strandedness value computation.
#' 
#' @param p (Default 0.6) Numeric value for the exact binomial test performed
#' for the strandedness value of each feature, representing the hypothesized
#' probability of success (i.e. the strandedness value expected for a 
#' non-stranded dataset).
#'
#' @param verbose (Default TRUE) Logical value indicating if progress should be
#' reported through the execution of the code.
#'
#' @param BPPARAM An object of a \linkS4class{BiocParallelParam} subclass
#' to configure the parallel execution of the code. By default, a
#' \linkS4class{SerialParam} object is used, which does not use any
#' parallelization, with the flag \code{progress=TRUE} to show progress
#' through the calculations.
#'
#' @return A \linkS4class{SummarizedExperiment} with three assays:
#' \itemize{
#'   \item "strness": contains strandedness values for each feature and sample.
#'   \item "counts": number of reads aligning to each feature on the same 
#'          strand (according to \code{strandMode}).
#'   \item "counts_invstrand": number of reads aligning to each feature but on 
#'          the opposite strand (according to \code{strandMode}).
#' }
#' 
#' @details
#' Strandedness is computed for each feature and BAM file according to the
#' \code{strandMode} specified in case of paired-end data. For single-end,
#' the original strand of reads is used. All alignments from the BAM file(s) 
#' are considered to compute the strandedness.
#' 
#' The \code{p} value should be close to 0.5, representing the strandedness
#' expected for a non-stranded RNA-seq library.
#' 
#' @examples
#' features <- range(exonsBy(txdb, by="gene"))
#' features <- features[1:100]
#' sByFeature <- strnessByFeature(bamfiles, features, singleEnd=FALSE,
#'                             strandMode=2L)
#' sByFeature
#' 
#' @importFrom Rsamtools scanBamFlag ScanBamParam
#' @importFrom BiocParallel SerialParam bplapply bpnworkers
#' @importFrom SummarizedExperiment SummarizedExperiment
#' @importFrom methods is
#' @export
#' @rdname strandedness
strnessByFeature <- function(bfl, features, singleEnd=TRUE, strandMode=1L,
                            yieldSize=1000000L, ambiguous=FALSE, p=0.6,
                            verbose=TRUE,
                            BPPARAM=SerialParam(progressbar=verbose)) {
    
    yieldSize <- .checkYieldSize(yieldSize)
    bfl <- .checkBamFileListArgs(bfl, singleEnd, fragments=FALSE, yieldSize)
    if (is.na(strandMode))
        stop("invalid strand mode (must be 0, 1, or 2)")
    
    strandMode <- .checkStrandMode(strandMode)
    if (!is(features, "GRanges") && !is(features, "GRangesList"))
        stop("'features' object should be either a 'GRanges' or a", 
            "'GRangesList' object.")
    
    sbflags <- scanBamFlag(isUnmappedQuery=FALSE,
                            isProperPair=!singleEnd,
                            isSecondaryAlignment=FALSE,
                            isDuplicate=FALSE,
                            isNotPassingQualityControls=FALSE)
    param <- ScanBamParam(flag=sbflags)
    
    if (verbose)
        message("Start processing BAM file(s)")
    
    strbysm <- NULL
    if (length(bfl) > 1 && bpnworkers(BPPARAM) > 1) {
        verbose <- FALSE
        strnessByF <- bplapply(bfl, .strnessByF_oneBAM, features=features,
                            singleEnd=singleEnd, strandMode=strandMode,
                            param=param, ambiguous=ambiguous, p=p,
                            verbose=verbose, BPPARAM=BPPARAM)
    } else
        strnessByF <- lapply(bfl, .strnessByF_oneBAM, features=features,
                            singleEnd=singleEnd, strandMode=strandMode,
                            param=param, ambiguous=ambiguous, p=p,
                            verbose=verbose)
      
      names(strnessByF) <- gsub(pattern = ".bam", "", names(strnessByF), 
                                fixed = TRUE)
      strness <- do.call("cbind", lapply(strnessByF, function(x) x$strness))
      ov_c <- do.call("cbind", lapply(strnessByF, function(x) x$ov_c))
      ov_cinvs <- do.call("cbind", lapply(strnessByF, function(x) x$ov_cinvs))
      p.value <- do.call("cbind", lapply(strnessByF, function(x) x$p.value))
      
      alist <- list(strness = strness, counts = ov_c, 
                    counts_invstrand = ov_cinvs, p.value = p.value)
      strnessByF_se <- SummarizedExperiment(assays = alist, rowRanges=features)
      strnessByF_se
}

## Private function to issue a warning when the strandedness value is
## computed from a low number of alignments
#' @importFrom S4Vectors Hits countQueryHits countSubjectHits queryHits
#' @importFrom GenomicAlignments readGAlignmentPairs readGAlignments
#' @importFrom GenomicAlignments readGAlignmentsList findOverlaps invertStrand
#' @importFrom methods formalArgs
#' @importFrom GenomeInfoDb seqlevelsStyle
.strnessByF_oneBAM <- function(bf, features, singleEnd, strandMode=1L,
                                param, ambiguous, p, verbose) {
    if (isOpen(bf))
        close(bf)
    
    readfun <- .getReadFunction(singleEnd, fragments = FALSE)
    strand_arg <- "strandMode" %in% formalArgs(readfun)
    ov <- Hits(nLnode=0, nRnode=length(features), sort.by.query=TRUE)
    ovinvs <- Hits(nLnode=0, nRnode=length(features), sort.by.query=TRUE)
    open(bf)
    on.exit(close(bf))
    while (length(gal <- do.call(readfun, c(list(file = bf), list(param=param),
                                list(strandMode=strandMode)[strand_arg])))) {
        # gal <- .matchSeqinfo(gal, features, verbose)
        seqlevelsStyle(gal) <- seqlevelsStyle(features)[1]
        
        ## Finding overlaps using ovUnion method
        suppressWarnings(thisov <- findOverlaps(gal, features, 
                                                ignore.strand=FALSE))
        suppressWarnings(thisovinvs <- findOverlaps(invertStrand(gal), 
                                                features, ignore.strand=FALSE))
        ## Remove alignments overlapping > 1 feature
        r_to_keep <- which(countQueryHits(thisov) == 1L)
        thisov <- thisov[queryHits(thisov) %in% r_to_keep]
        r_to_keepinvs <- which(countQueryHits(thisovinvs) == 1L)
        thisovinvs <- thisovinvs[queryHits(thisovinvs) %in% r_to_keepinvs]
        ## if ambiguous = FALSE, remove ambiguous reads
        if (ambiguous) {
            ambaln <- intersect(queryHits(thisov), queryHits(thisovinvs))
            thisov <- thisov[!(queryHits(thisov) %in% ambaln)]
            thisovinvs <- thisovinvs[!(queryHits(thisovinvs) %in% ambaln)]
        }
        ov <- .appendHits(ov, thisov)
        ovinvs <- .appendHits(ovinvs, thisovinvs)
    }
    ov_c <- countSubjectHits(ov)
    ov_cinvs <- countSubjectHits(ovinvs)
    
    # strandedness
    wh <- which((ov_c + ov_cinvs) > 0)
    strness <- numeric(length(features))
    strness[wh] <- ov_c[wh] / (ov_c[wh] + ov_cinvs[wh])
    # binomial test on feature strandedness
    pval <- .strness_binomtest(ov_c, ov_cinvs, p)
    
    strnessByF <- list(strness = strness, ov_c = ov_c, ov_cinvs = ov_cinvs,
                        p.value = pval)
    strnessByF
}

#' @importFrom stats binom.test
.strness_binomtest <- function(ov_c, ov_cinvs, p) {
    pval <- numeric(length(ov_c))
    yesc <- ov_c > 0
    for (i in seq_len(sum(yesc))) {
        pval[yesc][i] <- binom.test(ov_c[yesc][i], 
                                    ov_c[yesc][i] + ov_cinvs[yesc][i], 
                                    p, alternative = "greater")$p.value
    }
    pval
}


