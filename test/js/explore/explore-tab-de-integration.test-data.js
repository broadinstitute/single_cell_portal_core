/**
 * @fileoverview: Data for high-level unit test for DE button display logic (SCP-4954)
 */

export const exploreParams = {
  "userSpecified": {
      "annotation": true,
      "cluster": true,
      "spatialGroups": true,
      "subsample": true
  },
  "cluster": "All Cells UMAP",
  "annotation": {
      "name": "biosample_id",
      "type": "group",
      "scope": "study"
  },
  "subsample": "all",
  "consensus": null,
  "spatialGroups": [],
  "genes": [],
  "geneList": "",
  "heatmapRowCentering": "",
  "scatterColor": "",
  "distributionPlot": "",
  "distributionPoints": "",
  "tab": "",
  "heatmapFit": "",
  "bamFileName": "",
  "ideogramFileId": "",
  "expressionFilter": [
      0,
      1
  ],
  "hiddenTraces": [],
  "isSplitLabelArrays": null
}

export const exploreInfo = {
  "cluster": {
      "numPoints": 48478,
      "isSubsampled": true
  },
  "taxonNames": [
      "Homo sapiens"
  ],
  "inferCNVIdeogramFiles": null,
  "bamBundleList": [],
  "uniqueGenes": [
      "A1BG",
      "A1BG-AS1", // Truncated almost all of 10000+ gene list, for brevity here
  ],
  "geneLists": [],
  "precomputedHeatmapLabel": null,
  "annotationList": {
      "default_cluster": "All Cells UMAP",
      "default_annotation": {
          "name": "biosample_id",
          "type": "group",
          "scope": "study",
          "values": [
              "BM02_6wkpp_r1",
              "BM12_6wk",
              "BM03_6wkpp_r1",
              "BM05_6wkpp",
              "BM08_6wk_r1",
              "BM08_6wkpp_r2",
              "BM13_6wk_r1",
              "BM13_6wk_r3",
              "BM07_7wkpp_r1",
              "BM11_6wk_r1",
              "BM01_7wkpp_r1",
              "BM02_13wkpp_t1",
              "BM08_13wk_r1",
              "BM05_12wk_r2",
              "BM03_13wk_r1",
              "BM03_13wkpp_r2",
              "BM01_13wkpp_r2",
              "BM13_12wk",
              "BM03_15dpp_r1",
              "BM08_15dpp_r1",
              "BM01_16dpp_r3",
              "BM07_17dpp_r2",
              "BM19_4dpp_r1",
              "BM02_5dpp_r1",
              "BM02_5dpp_r2",
              "BM03_5dpp_r1",
              "BM07_5dpp_r1",
              "BM01_5dpp_r1",
              "BM05_6dpp_r1",
              "BM11_5dpp_r1",
              "BM13_6dpp_r1",
              "BM07_13wk_r1",
              "BM01_23wk_r1",
              "BM03_24wk_r1",
              "BM03_24wk_r2",
              "BM08_24wk",
              "BM02_24wk_r2",
              "BM02_10dpp_r1",
              "BM03_10dpp_r1",
              "BM03_10dpp_r2",
              "BM01_12dpp_r1",
              "BM07_10dpp_r1",
              "BM13_13dpp_r1",
              "BM02_14dpp_r1",
              "BM04_t1_r2",
              "BM10_t1_r1",
              "BM06_t3",
              "BM04_t3_r1",
              "BT_t3_lot1",
              "BT_t3_old",
              "K1",
              "K2",
              "Kfresh",
              "BM07_25wk_lot711",
              "B2",
              "BM5",
              "BM06_t1_r1",
              "BM05_26wk_r1",
              "Bfresh"
          ],
          "identifier": "biosample_id--group--study"
      },
      "annotations": [
          {
              "name": "General_Celltype",
              "type": "group",
              "values": [
                  "LC2",
                  "GPMNB macrophages",
                  "neutrophils",
                  "B cells",
                  "T cells",
                  "removed",
                  "CSN1S1 macrophages",
                  "dendritic cells",
                  "LC1",
                  "eosinophils",
                  "fibroblasts"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "biosample_id",
              "type": "group",
              "values": [
                  "BM02_6wkpp_r1",
                  "BM12_6wk",
                  "BM03_6wkpp_r1",
                  "BM05_6wkpp",
                  "BM08_6wk_r1",
                  "BM08_6wkpp_r2",
                  "BM13_6wk_r1",
                  "BM13_6wk_r3",
                  "BM07_7wkpp_r1",
                  "BM11_6wk_r1",
                  "BM01_7wkpp_r1",
                  "BM02_13wkpp_t1",
                  "BM08_13wk_r1",
                  "BM05_12wk_r2",
                  "BM03_13wk_r1",
                  "BM03_13wkpp_r2",
                  "BM01_13wkpp_r2",
                  "BM13_12wk",
                  "BM03_15dpp_r1",
                  "BM08_15dpp_r1",
                  "BM01_16dpp_r3",
                  "BM07_17dpp_r2",
                  "BM19_4dpp_r1",
                  "BM02_5dpp_r1",
                  "BM02_5dpp_r2",
                  "BM03_5dpp_r1",
                  "BM07_5dpp_r1",
                  "BM01_5dpp_r1",
                  "BM05_6dpp_r1",
                  "BM11_5dpp_r1",
                  "BM13_6dpp_r1",
                  "BM07_13wk_r1",
                  "BM01_23wk_r1",
                  "BM03_24wk_r1",
                  "BM03_24wk_r2",
                  "BM08_24wk",
                  "BM02_24wk_r2",
                  "BM02_10dpp_r1",
                  "BM03_10dpp_r1",
                  "BM03_10dpp_r2",
                  "BM01_12dpp_r1",
                  "BM07_10dpp_r1",
                  "BM13_13dpp_r1",
                  "BM02_14dpp_r1",
                  "BM04_t1_r2",
                  "BM10_t1_r1",
                  "BM06_t3",
                  "BM04_t3_r1",
                  "BT_t3_lot1",
                  "BT_t3_old",
                  "K1",
                  "K2",
                  "Kfresh",
                  "BM07_25wk_lot711",
                  "B2",
                  "BM5",
                  "BM06_t1_r1",
                  "BM05_26wk_r1",
                  "Bfresh"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "donor_id",
              "type": "group",
              "values": [
                  "BM02",
                  "BM12",
                  "BM03",
                  "BM05",
                  "BM08",
                  "BM13",
                  "BM07",
                  "BM11",
                  "BM01",
                  "BM19",
                  "BM04",
                  "BM10",
                  "BM06",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "time_post_partum_days",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "time_post_partum_weeks",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "milk_stage",
              "type": "group",
              "values": [
                  "late_1",
                  "mature",
                  "early",
                  "late_2",
                  "transitional ",
                  "transitional",
                  "late_4",
                  "NA",
                  "late_3"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "infant_sick_YN",
              "type": "group",
              "values": [
                  "no",
                  "NA",
                  "yes"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "weaning_YN",
              "type": "group",
              "values": [
                  "NA",
                  "no",
                  "yes"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "mastisis_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "breast_soreness_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "directly_breastfeeding_YN",
              "type": "group",
              "values": [
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "any_formula_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "mother_medications_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "sunflower lecithin ",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "reported_menstruating_YN",
              "type": "group",
              "values": [
                  "no",
                  "N",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "maternal_medical_event_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "hormonal_birthcontrol_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "yes ",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "daycare_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "vaccines_reported_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "vaccines_list",
              "type": "group",
              "values": [
                  "NA",
                  "9/3 and 9/10 – a hep B booster in the hospital",
                  "no",
                  "5/9/19 hepatitis B",
                  "hepB ",
                  "vaccines on 5/15",
                  "(6/11) Dtap-hep, BIPV, rotavirus, pentavalent, big (PRP-T)",
                  "HepB",
                  "hepB (says 4/22 but probably 5/22?)",
                  "4/3/19 Hepatitis B (at birth) ",
                  "2 month vaccines",
                  "Dtap, Gib, IPV, PCU13, Rotavirus (8/16/19)",
                  "vaccines on 7/15",
                  "influenza (day prior to sample)"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "solid_foods_YN",
              "type": "group",
              "values": [
                  "no",
                  "NA",
                  "yes"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "reported_infant_medical_events_YN",
              "type": "group",
              "values": [
                  "no",
                  "yes",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "reported_infant_medical_events_description",
              "type": "group",
              "values": [
                  "NA",
                  "no",
                  "maybe a stomache bug ",
                  "hot and sleepy",
                  "jaundice",
                  "lounge tie removal mid july, vaccinations a few weeks prior ",
                  "runny nose",
                  "runny nose, diarrhea, vomitting, no fever",
                  "maybe still jaundice",
                  "stomach bug (August), runny nose (October/ currently)",
                  "influenza vaccine received on 4/8/19"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "library_preparation_protocol",
              "type": "group",
              "values": [
                  "EFO_0008919"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "library_preparation_protocol__ontology_label",
              "type": "group",
              "values": [
                  "Seq-Well"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "species",
              "type": "group",
              "values": [
                  "NCBITaxon_9606"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "species__ontology_label",
              "type": "group",
              "values": [
                  "Homo sapiens"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "geographical_region",
              "type": "group",
              "values": [
                  "GAZ_00003181"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "geographical_region__ontology_label",
              "type": "group",
              "values": [
                  "Boston"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "sex",
              "type": "group",
              "values": [
                  "female"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "disease",
              "type": "group",
              "values": [
                  "PATO_0000461"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "disease__ontology_label",
              "type": "group",
              "values": [
                  "normal"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "organ",
              "type": "group",
              "values": [
                  "UBERON_0001913"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "organ__ontology_label",
              "type": "group",
              "values": [
                  "milk"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "Age",
              "type": "group",
              "values": [
                  "31.0",
                  "34.0",
                  "33.0",
                  "29.0",
                  "35.0",
                  "32.0",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "biosample_type",
              "type": "group",
              "values": [
                  "PrimaryBioSample_BodyFluid"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "week_delivered",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "labor_induced_YN",
              "type": "group",
              "values": [
                  "Y",
                  "N",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "antibiotics_during_delivery",
              "type": "group",
              "values": [
                  "N",
                  "Y",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "delivery_mode",
              "type": "group",
              "values": [
                  "vaginal",
                  "C section",
                  "vaginal ",
                  "NA"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "ethnicity__ontology_label",
              "type": "group",
              "values": [
                  "European",
                  "Asian",
                  "Hispanic or Latin American",
                  "ancestry category"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "BMI_during_study",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "BMI_pre_pregnancy",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "ethnicity",
              "type": "group",
              "values": [
                  "HANCESTRO_0005",
                  "HANCESTRO_0008",
                  "HANCESTRO_0014",
                  "HANCESTRO_0004"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "cell_type",
              "type": "group",
              "values": [
                  "CL_0000066",
                  "CL_0000235",
                  "CL_0000775",
                  "CL_0000236",
                  "CL_0000084",
                  "CL_0000548",
                  "CL_0000451",
                  "CL_0000771",
                  "CL_0000057"
              ],
              "scope": "invalid",
              "is_differential_expression_enabled": false
          },
          {
              "name": "cell_type__ontology_label",
              "type": "group",
              "values": [
                  "epithelial cell",
                  "macrophage",
                  "neutrophil",
                  "B cell",
                  "T cell",
                  "animal cell",
                  "dendritic cell",
                  "eosinophil",
                  "fibroblast"
              ],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "organism_age",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "height_inches",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "height_meter",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "ext_weight_during_study_lbs",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "est_pre_pregnancy_weight_lbs",
              "type": "numeric",
              "values": [],
              "scope": "study",
              "is_differential_expression_enabled": false
          },
          {
              "name": "Epithelial Cell Subclusters",
              "type": "group",
              "values": [
                  "Secretory Lactocytes",
                  "LC1",
                  "KRT high lactocytes 1",
                  "Cycling Lactocytes",
                  "MT High Secretory Lactocytes",
                  "KRT high lactocytes 2"
              ],
              "scope": "cluster",
              "cluster_name": "Epithelial Cell Subclusters",
              "is_differential_expression_enabled": null
          }
      ],
      "clusters": [
          "All Cells UMAP",
          "Epithelial Cell Subclusters"
      ],
      "subsample_thresholds": {
          "All Cells UMAP": [
              20000,
              10000,
              1000
          ],
          "Epithelial Cell Subclusters": [
              20000,
              10000,
              1000
          ]
      }
  },
  "clusterGroupNames": [
      "All Cells UMAP",
      "Epithelial Cell Subclusters"
  ],
  "spatialGroups": [],
  "differentialExpression": [
      {
          "cluster_name": "All Cells UMAP",
          "annotation_name": "General_Celltype",
          "annotation_scope": "study",
          "select_options": [
              [
                  "LC2",
                  "cluster_umap_txt--General_Celltype--LC2--study--wilcoxon.tsv"
              ],
              [
                  "GPMNB macrophages",
                  "cluster_umap_txt--General_Celltype--GPMNB_macrophages--study--wilcoxon.tsv"
              ],
              [
                  "LC1",
                  "cluster_umap_txt--General_Celltype--LC1--study--wilcoxon.tsv"
              ],
              [
                  "neutrophils",
                  "cluster_umap_txt--General_Celltype--neutrophils--study--wilcoxon.tsv"
              ],
              [
                  "B cells",
                  "cluster_umap_txt--General_Celltype--B_cells--study--wilcoxon.tsv"
              ],
              [
                  "T cells",
                  "cluster_umap_txt--General_Celltype--T_cells--study--wilcoxon.tsv"
              ],
              [
                  "dendritic cells",
                  "cluster_umap_txt--General_Celltype--dendritic_cells--study--wilcoxon.tsv"
              ],
              [
                  "CSN1S1 macrophages",
                  "cluster_umap_txt--General_Celltype--CSN1S1_macrophages--study--wilcoxon.tsv"
              ],
              [
                  "eosinophils",
                  "cluster_umap_txt--General_Celltype--eosinophils--study--wilcoxon.tsv"
              ],
              [
                  "fibroblasts",
                  "cluster_umap_txt--General_Celltype--fibroblasts--study--wilcoxon.tsv"
              ]
          ]
      },
      {
          "cluster_name": "All Cells UMAP",
          "annotation_name": "cell_type__ontology_label",
          "annotation_scope": "study",
          "select_options": [
              [
                  "epithelial cell",
                  "cluster_umap_txt--cell_type__ontology_label--epithelial_cell--study--wilcoxon.tsv"
              ],
              [
                  "macrophage",
                  "cluster_umap_txt--cell_type__ontology_label--macrophage--study--wilcoxon.tsv"
              ],
              [
                  "neutrophil",
                  "cluster_umap_txt--cell_type__ontology_label--neutrophil--study--wilcoxon.tsv"
              ],
              [
                  "B cell",
                  "cluster_umap_txt--cell_type__ontology_label--B_cell--study--wilcoxon.tsv"
              ],
              [
                  "T cell",
                  "cluster_umap_txt--cell_type__ontology_label--T_cell--study--wilcoxon.tsv"
              ],
              [
                  "dendritic cell",
                  "cluster_umap_txt--cell_type__ontology_label--dendritic_cell--study--wilcoxon.tsv"
              ],
              [
                  "eosinophil",
                  "cluster_umap_txt--cell_type__ontology_label--eosinophil--study--wilcoxon.tsv"
              ],
              [
                  "fibroblast",
                  "cluster_umap_txt--cell_type__ontology_label--fibroblast--study--wilcoxon.tsv"
              ]
          ]
      }
  ],
  "hasImageCache": [],
  "imageFiles": [],
  "clusterPointAlpha": 1,
  "colorProfile": null,
  "bucketId": "fc-febd4c65-881d-497f-b101-01a7ec427e6a",
  "canEdit": true
}
