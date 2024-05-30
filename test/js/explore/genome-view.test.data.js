// Example response content from SCP JS API fetchTrackInfo
export const trackInfo = {
  tracks: [
    {
      format: 'bam',
      name: 'pbmc_unsorted_3k_atac_possorted_bam.bam',
      url: 'https://www.googleapis.com/storage/v1/b/fc-123/o/pbmc_unsorted_3k_atac_possorted_bam.bam?alt=media',
      indexUrl: 'https://www.googleapis.com/storage/v1/b/fc-123/o/pbmc_unsorted_3k_atac_possorted_bam.bam.bai?alt=media',
      genomeAssembly: 'GRCh38',
      genomeAnnotation: {
        _id: {
          $oid: '5ec4299e62561815caad7113'
        },
        bucket_id: 'fc-2f8ef4c0-b7eb-44b1-96fe-a07f0ea9a982',
        genome_assembly_id: {
          $oid: '5df8fcf3421aa920fe7a1010'
        },
        index_link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz.tbi',
        link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz',
        name: 'Ensembl 94',
        release_date: '2018-07-01'
      }
    }, {
      format: 'bed',
      name: 'pbmc_3k_atac_fragments.possorted.bed.gz',
      url: 'https://www.googleapis.com/storage/v1/b/fc-123/o/pbmc_3k_atac_fragments.possorted.bed.gz?alt=media',
      indexUrl: 'https://www.googleapis.com/storage/v1/b/fc-123/o/pbmc_3k_atac_fragments.possorted.bed.gz.tbi?alt=media',
      genomeAssembly: 'GRCh38',
      genomeAnnotation: {
        _id: {
          $oid: '5ec4299e62561815caad7113'
        },
        bucket_id: 'fc-2f8ef4c0-b7eb-44b1-96fe-a07f0ea9a982',
        genome_assembly_id: {
          $oid: '5df8fcf3421aa920fe7a1010'
        },
        index_link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz.tbi',
        link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz',
        name: 'Ensembl 94',
        release_date: '2018-07-01'
      }
    }
  ],
  gtfFiles: {
    GRCh38: {
      genome_annotations: {
        name: {
          _id: {
            $oid: '5ec4299e62561815caad7113'
          },
          bucket_id: 'fc-456',
          genome_assembly_id: {
            $oid: 'abcd'
          },
          index_link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz.tbi',
          link: 'reference_data/homo_sapiens/GRCh38_GCA_000001405.27/ensembl_94/Homo_sapiens.GRCh38.94.possorted.gtf.gz',
          name: 'Ensembl 94',
          release_date: '2018-07-01'
        },
        url: 'https://www.googleapis.com/storage/v1/b/fc-456/o/reference_data%2Fhomo_sapiens%2FGRCh38_GCA_000001405.27%2Fensembl_94%2FHomo_sapiens.GRCh38.94.possorted.gtf.gz',
        indexUrl: 'https://www.googleapis.com/storage/v1/b/fc-456/o/reference_data%2Fhomo_sapiens%2FGRCh38_GCA_000001405.27%2Fensembl_94%2FHomo_sapiens.GRCh38.94.possorted.gtf.gz.tbi'
      }
    }
  }
}
