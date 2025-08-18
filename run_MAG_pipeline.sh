#!/bin/bash

# This version of biobakery is a patch because the latest versions of Humann (v3.9) and Metaphlan (v4.2.2) are not compatible
# This version runs the latests KneadData, Humann v3.9 and Metaphlan v3.1 which are compatible
# The BioBakery team working to release a new version of Humann that will be forward compatible with Metaphlan

# --- Load BioBakery conda environment before running this script!!! ---
#
# miniforge3
# conda activate biobakery_patch

echo "Starting time"
echo `date`
echo ""

# --- Help Menu ---
usage() {
    echo ""
    echo "BioBakery4 Core Pipeline Runner"
    echo ""
    echo "Usage:"
    echo "  biobakery4_core_run.sh -type <paired|single> -threads <num_threads> \\"
    echo "                         -read1 <read1.fq> -read2 <read2.fq> -out <output_dir>"
    echo "  OR"
    echo "  biobakery4_core_run.sh -type single -threads <num_threads> \\"
    echo "                         -unpaired <read.fq> -out <output_dir>"
    echo ""
    echo "Options:"
    echo "  -type       Type of input: 'paired' or 'single'"
    echo "  -threads    Number of threads for parallel processing"
    echo "  -read1      Forward reads file (required for paired-end)"
    echo "  -read2      Reverse reads file (required for paired-end)"
    echo "  -unpaired   Reads file (required for single-end)"
    echo "  -out        Output directory name"
    echo "  -h          Show this help menu"
    echo ""
    exit 0
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -type) TYPE="$2"; shift ;;
        -threads) THREADS="$2"; shift ;;
        -read1) READ1="$2"; shift ;;
        -read2) READ2="$2"; shift ;;
        -unpaired) UNPAIRED="$2"; shift ;;
        -out) OUTDIR="$2"; shift ;;
        -h) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

# --- Validation ---
if [[ -z "$TYPE" || -z "$THREADS" || -z "$OUTDIR" ]]; then
    echo "❌ Missing required parameters."
    usage
fi

if [[ "$TYPE" == "paired" ]]; then
    if [[ -z "$READ1" || -z "$READ2" ]]; then
        echo "❌ For paired-end data, -read1 and -read2 are required."
        usage
    fi
elif [[ "$TYPE" == "single" ]]; then
    if [[ -z "$UNPAIRED" ]]; then
        echo "❌ For single-end data, -unpaired is required."
        usage
    fi
else
    echo "❌ Invalid type: $TYPE. Must be 'paired' or 'single'."
    usage
fi

mkdir -p "$OUTDIR"

# --- Run KneadData ---
echo "Running KneadData..."
if [[ "$TYPE" == "paired" ]]; then
    kneaddata -i1 "$READ1" \
              -i2 "$READ2" \
              -o "${OUTDIR}/kneaddata_output" \
              -t "$THREADS" \
              -db /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/KneadData_DB/ \
              --bypass-trf
else
    kneaddata -un "$UNPAIRED" \
              -o "${OUTDIR}/kneaddata_output" \
              -t "$THREADS" \
              -db /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/KneadData_DB/ \
              --bypass-trf
fi

# The fastq output by kneaddata that has been QC'd, trimmed, and host reads removed.
if [[ "$TYPE" == "paired" ]]; then
    CLEANED1=$(find "${OUTDIR}/kneaddata_output" -name '*_kneaddata_paired_1.fastq' | head -n 1)
    CLEANED2=$(find "${OUTDIR}/kneaddata_output" -name '*_kneaddata_paired_2.fastq' | head -n 1)
    CONCAT_CLEANED="${OUTDIR}/concatenated_kneaddata.fastq"
    cat "$CLEANED1" "$CLEANED2" > "$CONCAT_CLEANED"
else
    CLEANED=$(find "${OUTDIR}/kneaddata_output" -name '*_kneaddata.fastq' | head -n 1)
fi

# --- Run MetaPhlAn ---
echo "Running MetaPhlAn..."
if [[ "$TYPE" == "paired" ]]; then
    metaphlan --input_type fastq \
              --nproc "$THREADS" \
              --bowtie2db /bioinfo/apps/all_apps/miniforge3/envs/biobakery_patch/lib/python3.7/site-packages/metaphlan/metaphlan_databases/ \
              --index mpa_v31_CHOCOPhlAn_201901 \
              --output_file "${OUTDIR}/metaphlan_profile.txt" \
              --add_viruses \
              "$CONCAT_CLEANED"
else
    metaphlan --input_type fastq \
              --nproc "$THREADS" \
              --bowtie2db /bioinfo/apps/all_apps/miniforge3/envs/biobakery_patch/lib/python3.7/site-packages/metaphlan/metaphlan_databases/ \
              --index mpa_v31_CHOCOPhlAn_201901 \
              --output_file "${OUTDIR}/metaphlan_profile.txt" \
              --add_viruses \
              "$CLEANED"
fi

# --- Run HUMAnN ---
echo "Running HUMAnN..."
if [[ "$TYPE" == "paired" ]]; then
    humann --input "$CONCAT_CLEANED" \
           --output "${OUTDIR}/humann_output" \
           --threads "$THREADS" \
           --taxonomic-profile "${OUTDIR}/metaphlan_profile.txt" \
           --nucleotide-database /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/Humann_DB/chocophlan/ \
           --protein-database /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/Humann_DB/uniref/
else
    humann --input "$CLEANED" \
           --output "${OUTDIR}/humann_output" \
           --threads "$THREADS" \
           --taxonomic-profile "${OUTDIR}/metaphlan_profile.txt" \
           --nucleotide-database /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/Humann_DB/chocophlan/ \
           --protein-database /bioinfo/apps/all_apps/miniforge3/envs/biobakery4/Humann_DB/uniref/
fi

# --- Run MegaHit ---
echo "Running MegaHit..."
if [[ "$TYPE" == "paired" ]]; then
    megahit -t "$THREADS" \
            -1 "$CLEANED1" \
            -2 "$CLEANED2" \
            -o "${OUTDIR}/megahit_assembly"
else
    megahit -t "$THREADS" \
            -r "$CLEANED" \
            -o "${OUTDIR}/megahit_assembly"
fi

echo "Done! All outputs are organized in: $OUTDIR"

echo ""
echo "Finish time"
echo `date`
echo ""
