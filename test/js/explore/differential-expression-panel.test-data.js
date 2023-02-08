export const exploreInfo = {
  'taxonNames': [
    'Homo sapiens'
  ],
  'differentialExpression': [
    {
      'cluster_name': 'Epithelial Cells UMAP',
      'annotation_name': 'directly_breastfeeding_YN',
      'annotation_scope': 'study',
      'select_options': [
        [
          'yes',
          'Epithelial_Cells_UMAP--directly_breastfeeding_YN--yes--study--wilcoxon.tsv'
        ],
        [
          'NA',
          'Epithelial_Cells_UMAP--directly_breastfeeding_YN--NA--study--wilcoxon.tsv'
        ]
      ]
    },
    {
      'cluster_name': 'Epithelial Cells UMAP',
      'annotation_name': 'Epithelial Cell Subclusters',
      'annotation_scope': 'cluster',
      'select_options': [
        [
          'Secretory Lactocytes',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--Secretory_Lactocytes--cluster--wilcoxon.tsv'
        ],
        [
          'LC1',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--LC1--cluster--wilcoxon.tsv'
        ],
        [
          'KRT high lactocytes 1',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--KRT_high_lactocytes_1--cluster--wilcoxon.tsv'
        ],
        [
          'Cycling Lactocytes',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--Cycling_Lactocytes--cluster--wilcoxon.tsv'
        ],
        [
          'MT High Secretory Lactocytes',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--MT_High_Secretory_Lactocytes--cluster--wilcoxon.tsv'
        ],
        [
          'KRT high lactocytes 2',
          'Epithelial_Cells_UMAP--Epithelial_Cell_Subclusters--KRT_high_lactocytes_2--cluster--wilcoxon.tsv'
        ]
      ]
    },
    {
      'cluster_name': 'Epithelial Cells UMAP',
      'annotation_name': 'mother_medications_YN',
      'annotation_scope': 'study',
      'select_options': [
        [
          'no',
          'Epithelial_Cells_UMAP--mother_medications_YN--no--study--wilcoxon.tsv'
        ],
        [
          'yes',
          'Epithelial_Cells_UMAP--mother_medications_YN--yes--study--wilcoxon.tsv'
        ],
        [
          'sunflower lecithin ',
          'Epithelial_Cells_UMAP--mother_medications_YN--sunflower_lecithin_--study--wilcoxon.tsv'
        ],
        [
          'NA',
          'Epithelial_Cells_UMAP--mother_medications_YN--NA--study--wilcoxon.tsv'
        ]
      ]
    },
    {
      'cluster_name': 'Epithelial Cells UMAP',
      'annotation_name': 'reported_menstruating_YN',
      'annotation_scope': 'study',
      'select_options': [
        [
          'no',
          'Epithelial_Cells_UMAP--reported_menstruating_YN--no--study--wilcoxon.tsv'
        ],
        [
          'N',
          'Epithelial_Cells_UMAP--reported_menstruating_YN--N--study--wilcoxon.tsv'
        ],
        [
          'NA',
          'Epithelial_Cells_UMAP--reported_menstruating_YN--NA--study--wilcoxon.tsv'
        ]
      ]
    },

    {
      'cluster_name': 'All Cells UMAP',
      'annotation_name': 'reported_infant_medical_events_description',
      'annotation_scope': 'study',
      'select_options': [
        [
          'NA',
          'All_Cells_UMAP--reported_infant_medical_events_description--NA--study--wilcoxon.tsv'
        ],
        [
          'no',
          'All_Cells_UMAP--reported_infant_medical_events_description--no--study--wilcoxon.tsv'
        ],
        [
          'maybe a stomache bug ',
          'All_Cells_UMAP--reported_infant_medical_events_description--maybe_a_stomache_bug_--study--wilcoxon.tsv'
        ],
        [
          'hot and sleepy',
          'All_Cells_UMAP--reported_infant_medical_events_description--hot_and_sleepy--study--wilcoxon.tsv'
        ],
        [
          'jaundice',
          'All_Cells_UMAP--reported_infant_medical_events_description--jaundice--study--wilcoxon.tsv'
        ],
        [
          'lounge tie removal mid july, vaccinations a few weeks prior ',
          'All_Cells_UMAP--reported_infant_medical_events_description--lounge_tie_removal_mid_july__vaccinations_a_few_weeks_prior_--study--wilcoxon.tsv'
        ],
        [
          'runny nose',
          'All_Cells_UMAP--reported_infant_medical_events_description--runny_nose--study--wilcoxon.tsv'
        ],
        [
          'runny nose, diarrhea, vomitting, no fever',
          'All_Cells_UMAP--reported_infant_medical_events_description--runny_nose__diarrhea__vomitting__no_fever--study--wilcoxon.tsv'
        ],
        [
          'maybe still jaundice',
          'All_Cells_UMAP--reported_infant_medical_events_description--maybe_still_jaundice--study--wilcoxon.tsv'
        ],
        [
          'stomach bug (August), runny nose (October/ currently)',
          'All_Cells_UMAP--reported_infant_medical_events_description--stomach_bug__August___runny_nose__October__currently_--study--wilcoxon.tsv'
        ],
        [
          'influenza vaccine received on 4/8/19',
          'All_Cells_UMAP--reported_infant_medical_events_description--influenza_vaccine_received_on_4_8_19--study--wilcoxon.tsv'
        ]
      ]
    }
  ],
  'annotationList': {
    'annotations': [
      {
        'name': 'General_Celltype',
        'type': 'group',
        'values': [
          'LC2',
          'GPMNB macrophages',
          'neutrophils',
          'B cells',
          'T cells',
          'removed',
          'CSN1S1 macrophages',
          'dendritic cells',
          'LC1',
          'eosinophils',
          'fibroblasts'
        ],
        'scope': 'study'
      },
      {
        'name': 'time_post_partum_days',
        'type': 'numeric',
        'values': [],
        'scope': 'study'
      },
      {
        'name': 'milk_stage',
        'type': 'group',
        'values': [
          'late_1',
          'mature',
          'early',
          'late_2',
          'transitional ',
          'transitional',
          'late_4',
          'NA',
          'late_3'
        ],
        'scope': 'study'
      },
      {
        'name': 'vaccines_list',
        'type': 'group',
        'values': [
          'NA',
          '9/3 and 9/10 – a hep B booster in the hospital',
          'no',
          '5/9/19 hepatitis B',
          'hepB ',
          'vaccines on 5/15',
          '(6/11) Dtap-hep, BIPV, rotavirus, pentavalent, big (PRP-T)',
          'HepB',
          'hepB (says 4/22 but probably 5/22?)',
          '4/3/19 Hepatitis B (at birth) ',
          '2 month vaccines',
          'Dtap, Gib, IPV, PCU13, Rotavirus (8/16/19)',
          'vaccines on 7/15',
          'influenza (day prior to sample)'
        ],
        'scope': 'study'
      },
      {
        'name': 'Epithelial Cell Subclusters',
        'type': 'group',
        'values': [
          'Secretory Lactocytes',
          'LC1',
          'KRT high lactocytes 1',
          'Cycling Lactocytes',
          'MT High Secretory Lactocytes',
          'KRT high lactocytes 2'
        ],
        'scope': 'cluster',
        'cluster_name': 'Epithelial Cells UMAP'
      }
    ],
    'clusters': [
      'Epithelial Cells UMAP',
      'All Cells UMAP'
    ]
  },
  'clusterGroupNames': [
    'Epithelial Cells UMAP',
    'All Cells UMAP'
  ],
  'bucketId': 'fc-65379b91-5ded-4d28-8e51-ada209542117'
}
