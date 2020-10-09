version 1.0

## Copyright Broad Institute, 2020
## 
## This WDL implements a basic joint discovery workflow with GATK4. It is based 
## on the Best Practices pipeline published by the GATK team here:
## https://github.com/gatk-workflows/gatk4-germline-snps-indels/blob/master/JointGenotyping.wdl
## However this workflow is not vetted for production work and is only intended 
## for testing, demonstration and teaching purposes.
##
## Requirements/expectations :
## - One or more GVCFs produced by HaplotypeCaller in GVCF mode 
##
## Outputs :
## - A VCF file and its index, containing variants joint-called from the input samples,
##   without any filtering applied after calling.
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

# Basic Joint Genotyping (not Best Practices, just demo)
workflow BasicJointGenotyping {

  input {
    Array[File] input_gvcfs
    File interval_list
    String callset_name

    File ref_fasta
    File ref_fasta_index
    File ref_dict

    String gatk_path = "/gatk/gatk"
    String gatk_docker = "broadinstitute/gatk:4.1.8.1"
  }

  scatter (input_gvcf in input_gvcfs) {

    call IndexFile {
      input: 
        input_file = input_gvcf,
        output_suffix = ".tbi",
        gatk_path = gatk_path,
        docker = gatk_docker
    }
  }

  Array[String] calling_intervals = read_lines(interval_list)

  scatter (interval in calling_intervals) {

    call ImportGVCFs {
      input:
        input_gvcfs = input_gvcfs,
        input_gvcf_indices = IndexFile.output_index,
        workspace_dir_name = "genomicsdb",
        interval = interval,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        gatk_path = gatk_path,
        docker = gatk_docker
    }

    call GenotypeGVCFs {
      input:
        workspace_tar = ImportGVCFs.output_workspace,
        interval = interval,
        output_vcf_filename = callset_name + "_scatter.vcf.gz",
        output_index_suffix = ".tbi",
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        ref_dict = ref_dict,
        gatk_path = gatk_path,
        docker = gatk_docker
    }
  } 

  call MergeVCFs {
    input:
      input_vcfs = GenotypeGVCFs.output_vcf,
      input_vcf_indices = GenotypeGVCFs.output_vcf_index,
      merged_vcf_filename = callset_name + ".vcf.gz",
      output_index_suffix = ".tbi",
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      gatk_path = gatk_path,
      docker = gatk_docker
  }
}


task IndexFile {

  input {
    File input_file
    String output_suffix

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

  String index_name = input_file + output_suffix

  command {
    ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G ~{java_opt}" \
      IndexFeatureFile \
      -I ~{input_file} \
      -O ~{index_name}
  }

  runtime {
    docker: docker
    memory: machine_mem_gb + " GB"
    disks: "local-disk " + select_first([disk_space_gb, 100]) + if use_ssd then " SSD" else " HDD"
    preemptible: select_first([preemptible_attempts, 3])
  }

  output {
    File output_index = "~{index_name}"
  }

}

task ImportGVCFs {

  input {
    Array[File] input_gvcfs
    Array[File] input_gvcf_indices
    String interval
    String workspace_dir_name

    File ref_fasta
    File ref_fasta_index
    File ref_dict

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

  Int machine_mem_gb = select_first([mem_gb, 15])
  Int command_mem_gb = machine_mem_gb - 3

  String tarred_workspace_name = workspace_dir_name + ".tar"

  command <<<
    set -euo pipefail

    rm -rf ~{workspace_dir_name}

    ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G ~{java_opt}" \
      GenomicsDBImport \
      -V ~{sep=' -V' input_gvcfs} \
      -L ~{interval} \
      --genomicsdb-workspace-path ~{workspace_dir_name} \
      --batch-size 50 \
      --reader-threads 5 \
      --merge-input-intervals \
      --consolidate

    tar -cf ~{tarred_workspace_name} ~{workspace_dir_name}
  >>>

  runtime {
    docker: docker
    memory: machine_mem_gb + " GB"
    disks: "local-disk " + select_first([disk_space_gb, 100]) + if use_ssd then " SSD" else " HDD"
    preemptible: select_first([preemptible_attempts, 3])
  }

  output {
    File output_workspace = "~{tarred_workspace_name}"
  }
}

task GenotypeGVCFs {

  input {
    File workspace_tar
    File interval

    String output_vcf_filename
    String output_index_suffix

    File ref_fasta
    File ref_fasta_index
    File ref_dict

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

  command <<<
    set -euo pipefail

    tar -xf ~{workspace_tar}
    WORKSPACE=$(basename ~{workspace_tar} .tar)

    ~{gatk_path} --java-options "-Xmx~{command_mem_gb}G ~{java_opt}" \
      GenotypeGVCFs \
      -R ~{ref_fasta} \
      -V gendb://$WORKSPACE \
      -L ~{interval} \
      -O ~{output_vcf_filename} \
      -G StandardAnnotation -G AS_StandardAnnotation \
      --merge-input-intervals
  >>>

  runtime {
    docker: docker
    memory: machine_mem_gb + " GB"
    disks: "local-disk " + select_first([disk_space_gb, 100]) + if use_ssd then " SSD" else " HDD"
    preemptible: select_first([preemptible_attempts, 3])
  }

  output {
    File output_vcf = "~{output_vcf_filename}"
    File output_vcf_index = "~{output_vcf_filename + output_index_suffix}"
  }
}

task MergeVCFs {

  input {
    Array[File] input_vcfs
    Array[File] input_vcf_indices

    String merged_vcf_filename
    String output_index_suffix

    File ref_fasta
    File ref_fasta_index
    File ref_dict

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
      MergeVCFs \
      -I ~{sep=' -I' input_vcfs} \
      -O ~{merged_vcf_filename}
  }

  runtime {
    docker: docker
    memory: machine_mem_gb + " GB"
    disks: "local-disk " + select_first([disk_space_gb, 100]) + if use_ssd then " SSD" else " HDD"
    preemptible: select_first([preemptible_attempts, 3])
  }

  output {
    File output_vcf = "~{merged_vcf_filename}"
    File output_vcf_index = "~{merged_vcf_filename + output_index_suffix}"
  }

}