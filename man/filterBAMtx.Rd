% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/filterBAMtx.R
\name{filterBAMtx}
\alias{filterBAMtx}
\alias{filterBAMtxFlag}
\alias{testBAMtxFlag}
\title{Filter alignments in a BAM file using a transcriptome}
\usage{
filterBAMtx(
  object,
  path = ".",
  txflag = filterBAMtxFlag(),
  param = ScanBamParam(),
  yieldSize = 1e+06,
  verbose = TRUE,
  BPPARAM = SerialParam(progressbar = verbose)
)

filterBAMtxFlag(
  isSpliceCompatibleJunction = FALSE,
  isSpliceCompatibleExonic = FALSE,
  isIntronic = FALSE,
  isIntergenic = FALSE
)

testBAMtxFlag(flag, value)
}
\arguments{
\item{object}{gDNAx object obtained with the function 'gDNAdx()'.}

\item{path}{Directory where to write the output BAM files.}

\item{txflag}{A value from a call to the function 'filterBAMtxFlag()'.}

\item{param}{A 'ScanBamParam' object.}

\item{yieldSize}{(Default 1e6) Number of records in the input BAM file to
yield each time the file is read. The lower the value, the smaller memory
consumption, but in the case of large BAM files, values below 1e6 records
may decrease the overall performance.}

\item{verbose}{(Default TRUE) Logical value indicating if progress should be
reported through the execution of the code.}

\item{BPPARAM}{An object of a \linkS4class{BiocParallelParam} subclass
to configure the parallel execution of the code. By default, a
\linkS4class{SerialParam} object is used, which does not use any
parallelization, with the flag \code{progress=TRUE} to show progress
through the calculations.}

\item{isSpliceCompatibleJunction}{(Default FALSE) Logical value indicating
if spliced alignments overlapping a transcript in a 
"splice compatible" way should be included in the BAM file. For
paired-end reads, one or both alignments must have one or more splice
site(s) compatible with splicing. See 
\code{\link[GenomicAlignments:OverlapEncodings-class]{OverlapEncodings}}.}

\item{isSpliceCompatibleExonic}{(Default FALSE) Logical value indicating
if alignments without a splice site, but that overlap a transcript
in a "splice compatible" way, should be included in the BAM file.
For paired-end reads, none of the alignments must be spliced, and
each pair can be in different exons (or in the same one), as long as
they are "splice compatible". See 
\code{\link[GenomicAlignments:OverlapEncodings-class]{OverlapEncodings}}.}

\item{isIntronic}{(Default FALSE) Logical value indicating if alignments
mapping to introns should be included in the BAM file.}

\item{isIntergenic}{(Default FALSE) Logical value indicating if alignments
aligned to intergenic regions should be included in the BAM file.}

\item{flag}{A value from a call to the function 'filterBAMtxFlag()'.}

\item{value}{A character vector with the name of a flag.}
}
\value{
A vector of output filename paths.
}
\description{
Filter alignments in a BAM file using criteria based on a
transcriptome annotation.

Use 'filterBAMtxFlag()' to set what types of alignment in a BAM 
file should be filtered using the function 'filterBAMtx()',
among being splice-compatible with one or more junctions,
splice-compatible exonic, intronic or intergenic.
}
\examples{
library(gDNAinRNAseqData)

library(TxDb.Hsapiens.UCSC.hg38.knownGene)
txdb <- TxDb.Hsapiens.UCSC.hg38.knownGene

# Getting the 'gDNAx' object
bamfiles <- LiYu22subsetBAMfiles()
bamfiles <- bamfiles[c(1,7)] # using a subset of samples
gdnax <- gDNAdx(bamfiles, txdb, singleEnd=FALSE, strandMode=NA)

# Filtering splice-compatible alignments and writing them into new BAM files
fbf <- filterBAMtxFlag(isSpliceCompatibleJunction=TRUE,
                       isSpliceCompatibleExonic=TRUE)
dir <- tempdir()
fstats <- filterBAMtx(gdnax, path=dir, txflag=fbf)
list.files(dir, pattern="*.bam$")


# Filtering splice-compatible alignments and writing them into new BAM files
fbf <- filterBAMtxFlag(isSpliceCompatibleJunction=TRUE,
                       isSpliceCompatibleExonic=FALSE,
                       isIntronic=FALSE,
                       isIntergenic = FALSE)

testBAMtxFlag(fbf, "isSpliceCompatibleJunction")
                       
}
