//
// Run VEP to annotate VCF files
//

include { ENSEMBLVEP_VEP         } from '../../../modules/nf-core/ensemblvep/vep/main'
include { BCFTOOLS_PLUGINSCATTER } from '../../../modules/nf-core/bcftools/pluginscatter/main'
include { BCFTOOLS_CONCAT        } from '../../../modules/nf-core/bcftools/concat/main'
include { BCFTOOLS_SORT          } from '../../../modules/nf-core/bcftools/sort/main'
include { ENSEMBLVEP_DOWNLOAD } from '../../../modules/nf-core/ensemblvep/download/main.nf'

workflow VCF_ANNOTATE_ENSEMBLVEP {
    take:
    ch_vcf                      // channel: [ val(meta), path(vcf), path(tbi), [path(file1), path(file2)...] ]
    ch_fasta                    // channel: [ val(meta2), path(fasta) ] (optional)
    val_vep_genome              //   value: genome to use
    val_vep_species             //   value: species to use
    val_vep_cache_version       //   value: cache version to use
    ch_vep_cache                // channel: [ path(cache) ] (optional)
    ch_vep_extra_files          // channel: [ path(file1), path(file2)... ] (optional)
    val_sites_per_chunk         //   value: the amount of variants per scattered VCF

    main:
    def ch_versions  = Channel.empty()
    def ch_vep_input = Channel.empty()
    def ch_scatter   = Channel.empty()

    // Check if val_sites_per_chunk is set and scatter if it is
    if(val_sites_per_chunk) {
        //
        // Prepare the input VCF channel for scattering (split VCFs from custom files)
        //

        def ch_input = ch_vcf
            .multiMap { meta, vcf, tbi, custom_files ->
                vcf:    [ meta, vcf, tbi ]
                custom: [ meta, custom_files ]
            }

        //
        // Scatter the input VCFs into multiple VCFs. These VCFs contain the amount of variants
        // specified by `val_sites_per_chunk`. The lower this value is, the more files will be created
        //

        BCFTOOLS_PLUGINSCATTER(
            ch_input.vcf,
            val_sites_per_chunk,
            [],
            [],
            [],
            []
        )
        ch_versions = ch_versions.mix(BCFTOOLS_PLUGINSCATTER.out.versions.first())

        //
        // Run the annotation with EnsemblVEP
        //

        ch_scatter = BCFTOOLS_PLUGINSCATTER.out.scatter
            .map { meta, vcfs ->
                // This checks if multiple files were created using the scatter process
                // If multiple files are created, a list will be made as output of the process
                // So if the output isn't a list, there is always one file and if there is a list,
                // the amount of files in the list gets counted by .size()
                def is_list = vcfs instanceof ArrayList
                count = is_list ? vcfs.size() : 1
                [ meta, is_list ? vcfs : [vcfs], count ]
                // Channel containing the list of VCFs and the size of this list
            }
            .transpose(by:1) // Transpose on the VCFs => Creates an entry for each VCF in the list
            .combine(ch_input.custom, by: 0) // Re-add the sample specific custom files
            .multiMap { meta, vcf, count, custom_files ->
                // Define the new ID. The `_annotated` is to disambiguate the VEP output with its input
                def new_id = "${meta.id}${vcf.name.replace(meta.id,"").tokenize(".")[0]}_annotated" as String

                // Create channels: one with the VEP input and one with the original ID and count of scattered VCFs
                input:  [ meta + [id:new_id], vcf, custom_files ]
                count:  [ meta + [id:new_id], meta.id, count ]
            }

        ch_vep_input = ch_scatter.input
    } else {
        // Use the normal input when no scattering has to be performed
        ch_vep_input = ch_vcf.map { meta, vcf, _tbi, files -> [ meta, vcf, files ] }
    }

    // Annotate with ensemblvep if it's part of the requested tools
    ENSEMBLVEP_VEP(
        ch_vep_input,
        val_vep_genome,
        val_vep_species,
        val_vep_cache_version,
        ch_vep_cache,
        ch_fasta,
        ch_vep_extra_files
    )
    ch_versions = ch_versions.mix(ENSEMBLVEP_VEP.out.versions.first())

    def ch_vep_output  = ENSEMBLVEP_VEP.out.vcf
        .join(ENSEMBLVEP_VEP.out.tbi, failOnDuplicate:true, failOnMismatch:true)
    def ch_vep_reports = ENSEMBLVEP_VEP.out.report

    // Gather the files back together if they were scattered
    def ch_ready_vcfs = Channel.empty()
    if(val_sites_per_chunk) {
        //
        // Concatenate the VCFs back together with bcftools concat
        //

        def ch_concat_input = ch_vep_output
            .join(ch_scatter.count, failOnDuplicate:true, failOnMismatch:true)
            .map { meta, vcf, tbi, id, count ->
                def new_meta = meta + [id:id]
                [ groupKey(new_meta, count), vcf, tbi ]
            }
            .groupTuple() // Group the VCFs which need to be concatenated
            .map { meta, vcfs, tbis ->
                [ meta, vcfs, tbis ]
            }

        BCFTOOLS_CONCAT(
            ch_concat_input
        )
        ch_versions = ch_versions.mix(BCFTOOLS_CONCAT.out.versions.first())

        //
        // Sort the concatenate output (bcftools concat is unable to do this on its own)
        //

        BCFTOOLS_SORT(
            BCFTOOLS_CONCAT.out.vcf
        )
        ch_versions = ch_versions.mix(BCFTOOLS_SORT.out.versions.first())

        ch_ready_vcfs = BCFTOOLS_SORT.out.vcf
            .join(BCFTOOLS_SORT.out.tbi, failOnDuplicate:true, failOnMismatch:true)
    } else {
        ch_ready_vcfs = ch_vep_output
    }

    emit:
    vcf_tbi         = ch_ready_vcfs     // channel: [ val(meta), path(vcf), path(tbi) ]
    vep_reports     = ch_vep_reports    // channel: [ path(html) ]
    versions        = ch_versions       // channel: [ versions.yml ]
}
