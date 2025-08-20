# Define job parameters
CPUS="-c 16"       # Number of CPUs
MEM="-m 120"       # RAM usage in GB
NAME="-j biobake"  # Job name
OUT="-o out.log"   # Output log
ERR="-e out.err"   # Error log

# Define command to run
CMD="bash /bioinfo/work/1307926/scripts/run_biobakery_patch.sh -type single -threads 16 -unpaired reads.fastq -out reads.fastq.biobakery"

# Submit job
bsub $CPUS $MEM $NAME $OUT $ERR "$CMD"
