process VCF2DB {
    tag "$meta.id"
    label 'process_single'

    // WARN: Version information not provided by tool on CLI. Please update version string below when bumping container versions.
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/30/3013992b36b50c203acfd01b000d37f3753aee640238f6dd39d5e47f58e54d98/data':
        'community.wave.seqera.io/library/python_python-snappy_snappy_cyvcf2_vcf2db:9c1d7f361187f21a' }"

    input:
    tuple val(meta), path(vcf), path(ped)

    output:
    tuple val(meta), path("*.db") , emit: db
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def VERSION = "2020.02.24" // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    """
    vcf2db.py \\
        $vcf \\
        $ped \\
        ${prefix}.db \\
        $args

    sqlite3 ${prefix}.db 'CREATE INDEX idx_variant_impacts_id ON variant_impacts (variant_id)'
    sqlite3 ${prefix}.db 'ALTER TABLE variants ADD COLUMN tags varchar(255)'
    sqlite3 ${prefix}.db 'ALTER TABLE variants ADD COLUMN tags_user varchar(255)'
    sqlite3 ${prefix}.db 'ALTER TABLE variants ADD COLUMN notes varchar(255)'
    sqlite3 ${prefix}.db 'ALTER TABLE variants ADD COLUMN notes_user varchar(255)'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcf2db: $VERSION
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def VERSION = "2020.02.24" // WARN: Version information not provided by tool on CLI. Please update this string when bumping container versions.
    """
    touch ${prefix}.db

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcf2db: $VERSION
    END_VERSIONS
    """
}
