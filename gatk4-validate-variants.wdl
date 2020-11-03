version 1.0

## Copyright Broad Institute, 2020
## 
## This WDL performs format validation on a VCF (incl. GVCF) file
##
## Requirements/expectations :
## - One VCF file to validate (GVCF ok with `-gvcf` flag set to true)
##
## Output:
## - One text file containing the standard output from the validation command
##
## Cromwell version support 
## - Successfully tested with 53.1 
##
## Runtime parameters may be optimized for Broad's Google Cloud Platform implementation. 
## For program versions, see docker containers. 
##
## LICENSING : 
## This script is released under the WDL source code license (BSD-3) (see LICENSE in 
## https://github.com/openwdl/wdl). Note however that the programs it calls may 
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. See the respective containers
## for relevant information.

# WORKFLOW DEFINITION
workflow BasicVariantValidation {
  input {
    File input_vcf
    File input_vcf_index

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String gatk_path = "/gatk/gatk"
    String gatk_docker = "broadinstitute/gatk:4.1.8.1"
  }

  # Run the validation 
  call ValidateVariants {
    input:
      input_vcf = input_vcf,
      input_vcf_index = input_vcf_index,
      ref_fasta = ref_fasta,
      ref_fasta_index =ref_fasta_index,
      ref_dict = ref_dict,
      gatk_path = gatk_path,
      docker = gatk_docker
  }

  # Outputs that will be retained when execution is complete
  output {
    File validation_report = ValidateVariants.report
  }
}

# TASK DEFINITIONS

# Validate a VCF (incl. GVCF) using GATK ValidateVariants
task ValidateVariants {
  input {
    File input_vcf
    File input_vcf_index

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    # Validation options
    Boolean gvcf_mode = false
    Boolean skip_seq_dict = false
    Boolean skip_filtered = false

    # Environment parameters
    String gatk_path
    String docker

    # Resourcing parameters
    String? java_opt
    Int? mem_gb
    Int? disk_space_gb
    Boolean use_ssd = false
    Int? preemptible_attempts
  }
    
  Int machine_mem_gb = select_first([mem_gb, 7])
  Int command_mem_gb = machine_mem_gb - 1
 
  command {
    ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G ~{java_opt}" \
      ValidateVariants \
      -R ~{ref_fasta} \
      -V ~{input_vcf} \
      -gvcf ~{gvcf_mode} \
      --disable-sequence-dictionary-validation ~{skip_seq_dict} \
      --do-not-validate-filtered-records ~{skip_filtered} 
  }
  runtime {
    docker: docker
    memory: machine_mem_gb + " GB"
    disks: "local-disk " + select_first([disk_space_gb, 100]) + if use_ssd then " SSD" else " HDD"
    preemptible: select_first([preemptible_attempts, 3])
  }
  output {
    File report = stdout()
  }
}
