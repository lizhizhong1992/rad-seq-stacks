# unique stacks: Assemble exactly matching stacks for each individual from demultiplexed reads
# generated by the process_radtags script. Generates a set of tags, senps and alleles files
# per infividual and data set.
rule ustacks:
    input:
        "trimmed/{individual}/{individual}.1.fq.gz"
    output:
        "ustacks/M={max_individual_mm}.m={min_reads}/{individual}.tags.tsv.gz",
        "ustacks/M={max_individual_mm}.m={min_reads}/{individual}.snps.tsv.gz",
        "ustacks/M={max_individual_mm}.m={min_reads}/{individual}.alleles.tsv.gz"
    params:
        outdir=get_outdir,
        hash=lambda w: individuals.loc[w.individual, "hash"]
    threads: 8
    conda:
        "../envs/stacks.yaml"
    log:
        "logs/ustacks/M={max_individual_mm}.m={min_reads}/{individual}.log"
    shell:
        "ustacks -p {threads} -f {input} -o {params.outdir} "
        "--name {wildcards.individual} "
        "-i {params.hash} "
        "-M {wildcards.max_individual_mm} "
        "-m {wildcards.min_reads} "
        "2> {log}"


def fmt_ustacks_input(wildcards, input):
    return ["-s {}".format(f[:-len(".tags.tsv.gz")]) for f in input.ustacks]

ustacks_individuals = expand(
    "ustacks/M={{max_individual_mm}}.m={{min_reads}}/{individual}.tags.tsv.gz",
    individual=individuals.id)


# catalog stacks: Build a catalog of loci from loci assembled by ustacks.
# Unify stacks from the individuals' tags, snps, and alleles files into
# one set of files per data set.
rule cstacks:
    input:
        ustacks=ustacks_individuals
    output:
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.tags.tsv.gz",
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.snps.tsv.gz",
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.alleles.tsv.gz"
    params:
        outdir=get_outdir,
        individuals=fmt_ustacks_input
    conda:
        "../envs/stacks.yaml"
    threads: 8
    log:
        "logs/cstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    shell:
        "cstacks -p {threads} {params.individuals} -o {params.outdir} 2> {log}"


# stacks: 
rule sstacks:
    input:
        ustacks=ustacks_individuals,
        cstacks=rules.cstacks.output[0]
    output:
        expand("stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{individual}.matches.tsv.gz",
               individual=individuals.id),
    params:
        outdir=get_outdir,
        individuals=fmt_ustacks_input,
        cstacks_dir=lambda w, input: os.path.dirname(input.cstacks)
    conda:
        "../envs/stacks.yaml"
    threads: 8
    log:
        "logs/sstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    shell:
        "sstacks -p {threads} {params.individuals} -c {params.cstacks_dir} "
        "-o {params.outdir} 2> {log}"


rule link_ustacks:
    input:
        "ustacks/M={max_individual_mm}.m={min_reads}/{individual}.{type}.tsv.gz"
    output:
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.{type}.tsv.gz",
    shell:
        "ln -s -r {input} {output}"


rule tsv2bam:
    input:
        sstacks=rules.sstacks.output,
        ustacks=expand("stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{{individual}}.{type}.tsv.gz",
                       type=["tags", "snps", "alleles"]),
        reads=["trimmed/{individual}/{individual}.1.fq.gz",
               "trimmed/{individual}/{individual}.2.fq.gz"]
    output:
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.matches.bam"
    params:
        sstacks_dir=lambda w, output: os.path.dirname(output[0]),
        read_dir=lambda w, input: os.path.dirname(input.reads[0])
    conda:
        "../envs/stacks.yaml"
    log:
        "logs/tsv2bam/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/{individual}.log"
    shell:
        "tsv2bam -s {wildcards.individual} -R {params.read_dir} "
        "-P {params.sstacks_dir} > {log}"


rule gstacks:
    input:
        bams=expand("stacks/n={{max_locus_mm}}.M={{max_individual_mm}}.m={{min_reads}}/{individual}.matches.bam",
                    individual=individuals.id),
        popmap="population-map.tsv"
    output:
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.calls",
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.fa.gz"
    params:
        outdir=get_outdir,
        bam_dir=lambda w, input: os.path.dirname(input.bams[0]),
        config=config["params"]["gstacks"]
    conda:
        "../envs/stacks.yaml"
    threads: 8
    log:
        "logs/gstacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    shell:
        "gstacks {params.config} -P {params.bam_dir} -O {params.outdir} "
        "-M {input.popmap} > {log}"


rule populations:
    input:
        "stacks/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/catalog.calls"
    output:
        "calls/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}/populations.snps.vcf"
    params:
        outdir=get_outdir,
        gstacks_dir=lambda w, input: os.path.dirname(input[0])
    conda:
        "../envs/stacks.yaml"
    threads: 8
    log:
        "logs/populations/n={max_locus_mm}.M={max_individual_mm}.m={min_reads}.log"
    shell:
        "populations -t {threads} -P {params.gstacks_dir} -O {params.outdir} --vcf > {log}"
