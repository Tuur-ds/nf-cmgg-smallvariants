//
// Concatenate the VCFs back together with bcftools concat
//

include { BCFTOOLS_CONCAT } from '../../../modules/nf-core/bcftools/concat/main'

workflow VCF_CONCAT_BCFTOOLS {
    take:
        ch_vcfs // channel: [ val(meta), path(vcf), path(tbi) ]

    main:

    def ch_versions = Channel.empty()

    ch_vcfs
        .map { meta, vcf, tbi=[] ->
            def new_meta = meta + [id:meta.sample ?: meta.family]
            [ groupKey(new_meta, meta.split_count), vcf, tbi ]
        }
        .groupTuple()
        .map { meta, vcfs, tbis ->
            [ meta, vcfs, tbis.findAll { tbi -> tbi != [] }]
        }
        .set { ch_concat_input }

    BCFTOOLS_CONCAT(
        ch_concat_input
    )
    ch_versions = ch_versions.mix(BCFTOOLS_CONCAT.out.versions.first())
    def ch_vcf_tbi = BCFTOOLS_CONCAT.out.vcf
        .join(BCFTOOLS_CONCAT.out.tbi, failOnDuplicate:true, failOnMismatch:true)

    emit:
    vcfs = ch_vcf_tbi       // channel: [ val(meta), path(vcf), path(tbi) ]

    versions = ch_versions  // channel: [ versions.yml ]
}
