# unique stacks: Assemble exactly matching stacks for each individual from demultiplexed reads
# generated by the process_radtags script. Generates a set of tags, senps and alleles files
# per infividual and data set.
rule ustacks:
    input:
        "analysis/trimmed/{individual}/{individual}.fq.gz"
    output:
        "analysis/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.tags.tsv.gz",
        "analysis/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.snps.tsv.gz",
        "analysis/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.alleles.tsv.gz"
    log:
        "logs/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.log"
    params:
        outdir=get_outdir,
        hash=lambda w: individuals.loc[w.individual, "hash"]
    conda:
        "../envs/stacks.yaml"
    benchmark:
        "benchmarks/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.txt"
    shell:
        "ustacks -f {input} -o {params.outdir} "
        "--name {wildcards.individual} "
        "-i {params.hash} "
        "-M {wildcards.max_individual_mm} "
        "-m {wildcards.min_reads} "
        "2> {log}"


ustacks_individuals = expand(
    "analysis/ustacks/M={{max_individual_mm}}.m={{min_reads}}/{individual}.tags.tsv.gz",
    individual=individuals.id)


# catalog stacks: Build a catalog of loci from loci assembled by ustacks.
# Unify stacks from the individuals' tags, snps, and alleles files into
# one set of files per data set.
rule cstacks:
    input:
        ustacks=ustacks_individuals
    output:
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.tags.tsv.gz",
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.snps.tsv.gz",
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.alleles.tsv.gz"
    log:
        "logs/cstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    params:
        outdir=get_outdir,
        individuals=fmt_ustacks_input
    conda:
        "../envs/stacks.yaml"
    benchmark:
        "benchmarks/cstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.txt"
    shell:
        "cstacks -n {wildcards.max_locus_mm} {params.individuals} "
        "-o {params.outdir} 2> {log}"


# search stacks: Search stacks of individuals (from ustacks) against the catalog (from cstacks)
# Generates a matches.tsv file for each data set which contains allele information for the data set.
rule sstacks:
    input:
        ustacks=ustacks_individuals,
        cstacks=rules.cstacks.output[0]
    output:
        expand("analysis/stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{individual}.matches.tsv.gz",
               individual=individuals.id),
    log:
        "logs/sstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    benchmark:
        "benchmarks/sstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.txt"
    params:
        outdir=get_outdir,
        individuals=fmt_ustacks_input,
        cstacks_dir=lambda w, input: os.path.dirname(input.cstacks)
    conda:
        "../envs/stacks.yaml"
    threads: 2
    shell:
        "sstacks {params.individuals} -c {params.cstacks_dir} -p {threads} "
        "-o {params.outdir} 2> {log}"


# Symlink ustacks results to avoid copying them to where tsv2bam expects them.
rule link_ustacks:
    input:
        "analysis/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.{type}.tsv.gz"
    output:
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.{type}.tsv.gz",
    log:
        "logs/ustacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.{type}.log"
    conda:
        "../envs/python.yaml"
    shell:
        "ln -s -r {input} {output} 2> {log}"


# Use the alleles saved in matches.tsv, the clustering information from ustacks, and the reads
# to generate a matches.bam file which contains the aligned reads for each loci.
rule tsv2bam:
    input:
        sstacks=rules.sstacks.output,
        ustacks=expand("analysis/stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{{individual}}.{type}.tsv.gz",
                       type=["tags", "snps", "alleles"]),
        reads="analysis/trimmed/{individual}/{individual}.fq.gz",
    output:
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.matches.bam"
    log:
        "logs/tsv2bam/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.log"
    benchmark:
        "benchmarks/tsv2bam/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.txt"
    params:
        sstacks_dir=lambda w, output: os.path.dirname(output[0]),
        read_dir=lambda w, input: os.path.dirname(input.reads)
    conda:
        "../envs/stacks.yaml"
    shell:
        "tsv2bam -s {wildcards.individual} "
        "-P {params.sstacks_dir} > {log}"


# genotype stacks: Use the aligned reads from the matches.bam and the population map to
# generate locus sequences (catalog.fa.gz) and SNP calls (catalog.calls).
#
# Note that BAM iostream errors in this rule can be caused by non-standard (i.e. non-CASAVA)
# name line patterns in input files.
rule gstacks:
    input:
        bams=expand("analysis/stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{individual}.matches.bam",
                    individual=individuals.id),
        popmap="resources/population-map.tsv"
    output:
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.calls",
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.fa.gz"
    log:
        "logs/gstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    benchmark:
        "benchmarks/gstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    params:
        outdir=get_outdir,
        bam_dir=lambda w, input: os.path.dirname(input.bams[0]),
        config=config["params"]["gstacks"]
    conda:
        "../envs/stacks.yaml"
    threads: 2
    shell:
        "gstacks {params.config} -P {params.bam_dir} -O {params.outdir} -t {threads} "
        "-M {input.popmap} >> {log}"


rule populations:
    input:
        "analysis/stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.calls"
    output:
        expand(
            "results/calls/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/populations.{e}",
            e=pop_suffixes(),
        ),
        report(
            expand(
                "results/calls/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/populations.{type}.tsv",
                type=["sumstats_summary", "sumstats"],
            ),
            caption="../report/sumstats.rst",
            category="Populations",
            subcategory="n={max_locus_mm}.M={max_individual_mm}.m={min_reads}",
        ),
        report(
            expand(
                "results/calls/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/populations.{type}.tsv",
                type=["haplotypes", "hapstats"],
            ),
            caption="../report/haplotypes.rst",
            category="Populations",
            subcategory=f"n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}",
        ),
    log:
        "logs/populations/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    benchmark:
        "benchmarks/populations/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    params:
        outdir=lambda w, output: os.path.dirname(output[0]),
        gstacks_dir=lambda w, input: os.path.dirname(input[0]),
        output_types=[f"--{t}" for t in config["params"]["populations"]["output_types"]],
    conda:
        "../envs/stacks.yaml"
    threads:
        config["params"]["populations"]["threads"]
    shell:
        "mkdir -p {params.outdir}; "
        "populations -t {threads} -P {params.gstacks_dir} "
        "-O {params.outdir} {params.output_types} > {log}"
