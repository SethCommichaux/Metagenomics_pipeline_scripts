#!/bin/bash
set -euo pipefail

### === Description ===
# This bash script chains various tools together to bin and annotate the MAGs within a metagenomic assembly.
# The inputs are a metagenomic assembly and the reads that were used to create the assembly.
#
# Before using make sure to load conda and the conda environment.
#
# miniforge3; conda activate MAG_Pipeline

# === USAGE ===
usage() {
  echo "Usage: $0 --assembly <assembly.fa> --reads1 <reads_1.fastq> [--reads2 <reads_2.fastq>] --threads <threads> --outdir <output_dir>"
  exit 1
}

# === PARSE ARGS ===
ARGS=$(getopt -o a:1:2:t:o: -l assembly:,reads1:,reads2:,threads:,outdir: -- "$@")
if [[ $? -ne 0 ]]; then
  usage
fi

eval set -- "$ARGS"

ASSEMBLY=""
READS1=""
READS2=""
THREADS=""
OUTDIR=""

while true; do
  case "$1" in
    -a|--assembly) ASSEMBLY="$2"; shift 2 ;;
    -1|--reads1)   READS1="$2"; shift 2 ;;
    -2|--reads2)   READS2="$2"; shift 2 ;;
    -t|--threads)  THREADS="$2"; shift 2 ;;
    -o|--outdir)   OUTDIR="$2"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done

# === CHECK REQUIRED ===
if [[ -z "$ASSEMBLY" || -z "$READS1" || -z "$THREADS" || -z "$OUTDIR" ]]; then
  usage
fi

# === Set file path variables to their real paths ===
ASSEMBLY=$(realpath "$ASSEMBLY")
READS1=$(realpath "$READS1")
OUTDIR=$(realpath "$OUTDIR")
if [[ -n "$READS2" ]]; then
  READS2=$(realpath "$READS2")
fi

# === SETUP ===
# mkdir -p "$OUTDIR"/{mapping,coverage,bins/metabat2,bins/maxbin2,bins/concoct,dastool,checkm2,gtdbtk,annotation}
cd "$OUTDIR"

# === STEP 1: Mapping ===
# bowtie2-build "$ASSEMBLY" mapping/assembly_index

# if [[ -n "$READS2" ]]; then
#  echo "🧬 Detected paired-end reads"
#  bowtie2 -x mapping/assembly_index -1 "$READS1" -2 "$READS2" | samtools view -bS - > mapping/mapped.bam
# else
#  echo "🧬 Detected single-end reads"
#  bowtie2 -x mapping/assembly_index -U "$READS1" | samtools view -bS - > mapping/mapped.bam
# fi

# samtools sort mapping/mapped.bam -o mapping/sorted.bam
# samtools index mapping/sorted.bam

# === STEP 2: Coverage ===
# jgi_summarize_bam_contig_depths --outputDepth coverage/depth.txt mapping/sorted.bam

# === STEP 3: MetaBAT2 ===
# metabat2 -i "$ASSEMBLY" -a coverage/depth.txt -o bins/metabat2/bin -t "$THREADS"

# === STEP 4: MaxBin2 ===
# run_MaxBin.pl -contig "$ASSEMBLY" -out bins/maxbin2/bin -abund coverage/depth.txt -thread "$THREADS"

# === STEP 5: CONCOCT ===
# cut_up_fasta.py "$ASSEMBLY" -c 10000 -o 0 --merge_last -b concoct_contigs.bed > concoct_contigs.fa
# concoct_coverage_table.py concoct_contigs.bed mapping/sorted.bam > concoct_coverage.tsv
# concoct --composition_file concoct_contigs.fa --coverage_file concoct_coverage.tsv -b bins/concoct/
# mkdir bins/concoct/extracted_bins
# extract_fasta_bins.py --output_path bins/concoct/extracted_bins concoct_contigs.fa bins/concoct/clustering_gt1000.csv

# === STEP 6: DASTool ===
DAS_Tool -i metabat2:"$OUTDIR"/bins/metabat2/,maxbin2:"$OUTDIR"/bins/maxbin2/,concoct:"$OUTDIR"/bins/concoct/extracted_bins/ \
        -l metabat2,maxbin2,concoct -o dastool/dastool -t "$THREADS" -c "$ASSEMBLY"

# === STEP 7: CheckM2 ===
checkm2 predict -x fa dastool/dastool_DASTool_bins/ checkm2/ --threads "$THREADS"

# === STEP 8: GTDB-Tk ===
gtdbtk classify_wf --genome_dir dastool/dastool_DASTool_bins/ --out_dir gtdbtk/ --cpus "$THREADS"

# === STEP 9: Annotation ===
for bin in dastool/dastool_DASTool_bins/*.fa; do
  BASENAME=$(basename "$bin" .fa)
  prokka --outdir annotation/"$BASENAME" --prefix "$BASENAME" "$bin" --cpus "$THREADS"
  # OR use Bakta:
  # bakta --db /path/to/bakta/db --output annotation/"$BASENAME" --prefix "$BASENAME" --threads "$THREADS" --genome "$bin"
done
