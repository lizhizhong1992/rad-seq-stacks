Summary statistics obtained from Stacks.

Used parameters:

* max_locus_mm (Number of mismatches allowed between sample loci): {{ snakemake.wildcards.max_locus_mm }}
* max_individual_mm (Number of mismatches allowed between stacks): {{ snakemake.wildcards.max_individual_mm }}
* min_reads (Minimum depth of coverage required to create a stack): {{ snakemake.wildcards.min_reads }}
