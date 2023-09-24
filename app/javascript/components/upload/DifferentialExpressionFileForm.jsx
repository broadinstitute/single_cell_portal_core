import React, { useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import _snakeCase from 'lodash/snakeCase'

import { FileTypeExtensions, matchingFormFiles, validateFile } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import Select from '~/lib/InstrumentedSelect'
import { clusterFileFilter } from './ClusteringStep'
import CreatableSelect from 'react-select/creatable'

const allowedFileExts = FileTypeExtensions.plainText
const requiredFields = [
  { label: 'Associated annotation', propertyName: 'differential_expression_file_info.annotation_name' },
  { label: 'Associated clustering', propertyName: 'differential_expression_file_info.clustering_association' },
  { label: 'Gene header', propertyName: 'differential_expression_file_info.gene_header' },
  { label: 'Group header', propertyName: 'differential_expression_file_info.group_header' },
  { label: 'Comparison group header', propertyName: 'differential_expression_file_info.comparison_group_header' },
  { label: 'Size metric', propertyName: 'differential_expression_file_info.size_metric' },
  { label: 'Significance metric', propertyName: 'differential_expression_file_info.significance_metric' }
]

/**
 * Get Select option groups "Inferred options" and "Other options"
 *
 * @param metricType {String} either "sizes" or "significances"
 * @param notes {Object} arrays of inferred metrics from raw file, by metric type
 * @param file {Object} study file object (not raw file)
 */
function inferOptions(headerType, file) {
  const notes = file.notes

  if (!notes) {
    return [[], null]
  }

  let key = 'deHeaders'
  if (['sizes', 'significances'].includes(headerType)) {
    key = 'metrics'
  }

  const inferredOptions =
    notes[headerType].map(opt => ({ label: opt, value: opt }))

  const notApplicableOption = { label: 'N/A', value: 'None' }
  if (headerType === 'comparisonGroupHeaders' && inferredOptions.length === 0) {
    inferredOptions.push(notApplicableOption)
  }

  const otherOptions =
    notes[key].filter(m => !notes[headerType].includes(m))
      .map(opt => ({ label: opt, value: opt }))

  const options = [
    { 'label': 'Inferred options', 'options': inferredOptions },
    { 'label': 'Other options', 'options': otherOptions }
  ]

  // E.g. significances -> significance_metric
  const singular = _snakeCase(headerType.slice(0, -1))
  const suffix = key == 'deHeaders' ? '' : '_metric'
  const snakeCaseMetricType = singular + suffix

  // Determine default value for select
  const allOptions = inferredOptions.concat(otherOptions)
  let defaultOption = allOptions.find(
    opt => opt.value === file.differential_expression_file_info[snakeCaseMetricType]
  ) || { label: notes[headerType][0], value: notes[headerType][0] }
  if (headerType === 'comparisonGroupHeaders' && !defaultOption['label']) {
    defaultOption = notApplicableOption
  }

  return [options, defaultOption]
}

/** Get Select option groups for required headers in author DE file */
function getAllHeaderOptions(file) {
  const [geneHeaderOptions, geneHeader] = inferOptions('geneHeaders', file)
  const [groupHeaderOptions, groupHeader] = inferOptions('groupHeaders', file)
  const [comparisonGroupHeaderOptions, comparisonGroupHeader] = inferOptions('comparisonGroupHeaders', file)
  const [sizeMetricOptions, sizeMetric] = inferOptions('sizes', file)
  const [significanceMetricOptions, significanceMetric] = inferOptions('significances', file)

  const allHeaderOptions = [
    [geneHeaderOptions, geneHeader],
    [groupHeaderOptions, groupHeader],
    [comparisonGroupHeaderOptions, comparisonGroupHeader],
    [sizeMetricOptions, sizeMetric],
    [significanceMetricOptions, significanceMetric]
  ]

  return allHeaderOptions
}

/** renders a form for editing/uploading a differential expression file */
export default function DifferentialExpressionFileForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  bucketName,
  isInitiallyExpanded,
  isAnnDataExperience,
  annotationsAvailOnStudy,
  menuOptions
}) {
  // TODO (SCP-5154) Add DE specific clientside validation
  const validationMessages = validateFile({ file, allFiles, allowedFileExts, requiredFields })

  const fragmentType = isAnnDataExperience ? 'cluster' : null

  const clusterFiles = matchingFormFiles(allFiles, clusterFileFilter, isAnnDataExperience, fragmentType)
  const clusterFileOptions = clusterFiles.map(cf => ({ label: cf.name, value: cf._id }))
  const associatedCluster = clusterFileOptions?.find(
    opt => opt.value === file.differential_expression_file_info.clustering_association
  )
  let annotationOptions = setAnnotationOptions()
  const associatedAnnotation = annotationOptions?.find(
    opt => opt.value === annotationIdentifier(file.differential_expression_file_info)
  )

  /* while mapping the computational methods constant to label/value pairs for the select
   update the labels to be more nicely human readable (e.g. remove snake casing) and remove
   the ambiguous 'custom' option
   */
  const compMethodOptions = menuOptions.de_computational_method.filter(
    compMethod => compMethod !== 'custom'
  ).map(
    opt => ({ label: opt.replace(/_/g, ' '), value: opt })
  )

  const associatedCompMethod = compMethodOptions?.find(
    opt => opt.value === file.differential_expression_file_info.computational_method
  )

  const headerOptions = getAllHeaderOptions(file)

  const [geneHeaderOptions, geneHeader] = headerOptions[0]
  const [groupHeaderOptions, groupHeader] = headerOptions[1]
  const [comparisonGroupHeaderOptions, comparisonGroupHeader] = headerOptions[2]
  const [sizeMetricOptions, sizeMetric] = headerOptions[3]
  const [significanceMetricOptions, significanceMetric] = headerOptions[4]

  /** extract annotation_name and annotation_scope and transform into URL-param like string */
  function annotationIdentifier(deInfoObject) {
    return `${deInfoObject.annotation_name}--group--${deInfoObject.annotation_scope}`
  }

  /** inverse of above, parse annotation attributes from delimited string */
  function extractAttributesFromId(identifier) {
    const annotationAttr = identifier.split('--')
    return { annotation_name: annotationAttr[0], annotation_scope: annotationAttr[2] }
  }

  /** format a label for the available annotations dropdown, noting annotation scope */
  function annotationLabel(annotation) {
    if (annotation.scope === 'cluster') {
      return `${annotation.name} (${annotation.cluster_name} only)`
    } else {
      return `${annotation.name}`
    }
  }

  /** handle a change in the associated cluster select */
  function updateAssociatedCluster(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { clustering_association: newVal } })
    annotationOptions = setAnnotationOptions()
  }

  /** handle a change in the associated annotation select */
  function updateAssociatedAnnotation(file, option) {
    let newVal = null
    if (option) {
      newVal = extractAttributesFromId(option.value)
    }
    updateFile(file._id, { differential_expression_file_info: newVal })
  }

  /** handle a change in the associated computational method select */
  function updateAssociatedCompMethod(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { computational_method: newVal } })
  }

  /** handle a change in any header or metric select */
  function updateDeFileInfo(file, optionsByAttr) {
    const info = {}
    Object.entries(optionsByAttr).forEach(([serverAttr, option]) => {
      let newVal = null
      if (option) {
        // TODO: Consider clearing any existing related warnings, e.g. if
        // there was a warning about a missing "gene" header.
        // The "Save & Upload" button becomes enabled even without clearing
        // any warnings upon selecting a value in e.g. the "Gene header" field,
        // so dynamically clearing warnings upon menu selection seems helpful
        // but not critical.
        newVal = option.value
      }
      info[serverAttr] = newVal
    })
    updateFile(file._id, { differential_expression_file_info: info })
  }

  /** set available annotations based off of selected cluster file */
  function setAnnotationOptions() {
    return annotationsAvailOnStudy?.filter(annot => {
      return (
        (annot.type === 'group' && annot.scope !== 'invalid') &&
        (annot.cluster_name === associatedCluster?.label || annot.scope === 'study')
      )
    }).map(
      cf => ({ label: annotationLabel(cf), value: `${cf.name}--${cf.type}--${cf.scope}` })
    )
  }

  if (file && geneHeader && !file.differential_expression_file_info.gene_header) {
    updateDeFileInfo(file, {
      'gene_header': geneHeader,
      'group_header': groupHeader,
      'comparison_group_header': comparisonGroupHeader,
      'size_metric': sizeMetric,
      'significance_metric': significanceMetric
    })
  }

  useEffect(() => {
    updateDeFileInfo(file, {
      'gene_header': geneHeader,
      'group_header': groupHeader,
      'comparison_group_header': comparisonGroupHeader,
      'size_metric': sizeMetric,
      'significance_metric': significanceMetric
    })
  }, [file?._id])

  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
    <div className="row">
      <div className="form-group col-md-3">
        <label className="labeled-select">Associated clustering
          <Select options={clusterFileOptions}
            data-analytics-name="differential-expression-associated-cluster-select"
            value={associatedCluster}
            placeholder="Select one..."
            onChange={val => updateAssociatedCluster(file, val)}/>
        </label>
      </div>
      <div className="form-group col-md-3">
        <label className="labeled-select">Associated annotation
          <Select options={annotationOptions}
            data-analytics-name="differential-expression-associated-annotation-select"
            value={associatedAnnotation}
            placeholder="Select one..."
            onChange={val => updateAssociatedAnnotation(file, val)}/>
        </label>
      </div>
      <div className="form-group col-md-6">
        <label className="labeled-select">Computational method
          {/* using CreateableSelect here so that users can add an option if their method isn't listed */}
          <CreatableSelect
            data-analytics-name="differential-expression-computational-method-select"
            options={compMethodOptions}
            value={associatedCompMethod}
            className="labeled-select"
            isClearable
            onChange={val => updateAssociatedCompMethod(file, val)}
            placeholder="Start typing to select or add your method or statistical test"
          />
        </label>
      </div>
    </div>
    {file.notes &&
    <>
      <div className="row">
        <div className="form-group col-md-2">
          <label className="labeled-select">Gene header
            <Select
              data-analytics-name="differential-expression-gene-header-select"
              options={geneHeaderOptions}
              defaultValue={geneHeader}
              value={geneHeader}
              className="labeled-select"
              onChange={val => updateDeFileInfo(file, { 'gene_header': val })}
              placeholder="Select header for gene names"
            />
          </label>
        </div>
        <div className="form-group col-md-2">
          <label className="labeled-select">Group header
            <span
              className="info-icon"
              data-analytics-name="differential-expression-download"
              data-toggle="tooltip"
              data-original-title='Column header that specifies the group of cells of interest for DE comparison.'
            >
              <FontAwesomeIcon icon={faInfoCircle}/>
            </span>
            <Select
              data-analytics-name="differential-expression-group-header-select"
              options={groupHeaderOptions}
              defaultValue={groupHeader}
              value={groupHeader}
              className="labeled-select"
              onChange={val => updateDeFileInfo(file, { 'group_header': val })}
              placeholder="Select metric for DE group"
            />
          </label>
        </div>
        <div className="form-group col-md-3" style={{ 'width': '18%' }}>
          <label className="labeled-select">Comparison group header
            <span
              className="info-icon"
              data-analytics-name="differential-expression-download"
              data-toggle="tooltip"
              data-original-title='Column header that specifies another group of cells to use in comparisons.  Leave as "N/A" if your DE file only has one-vs-rest comparisons.'
            >
              <FontAwesomeIcon icon={faInfoCircle}/>
            </span>
            <Select
              data-analytics-name="differential-expression-comparison-group-header-select"
              options={comparisonGroupHeaderOptions}
              defaultValue={comparisonGroupHeader}
              value={comparisonGroupHeader}
              className="labeled-select"
              onChange={val => updateDeFileInfo(file, { 'comparison_group_header': val })}
              placeholder="Select metric for DE comparison group"
            />
          </label>
        </div>
        <div className="form-group col-md-2">
          <label className="labeled-select">Size metric
            <Select
              data-analytics-name="differential-expression-size-metric-select"
              options={sizeMetricOptions}
              defaultValue={sizeMetric}
              value={sizeMetric}
              className="labeled-select"
              onChange={val => updateDeFileInfo(file, { 'size_metric': val })}
              placeholder="Select metric for DE size"
            />
          </label>
        </div>
        <div className="form-group col-md-2">
          <label className="labeled-select">Significance metric
            <Select
              data-analytics-name="differential-expression-significance-metric-select"
              options={significanceMetricOptions}
              defaultValue={significanceMetric}
              value={significanceMetric}
              className="labeled-select"
              onChange={val => updateDeFileInfo(file, { 'significance_metric': val })}
              placeholder="Select metric for DE significance"
            />
          </label>
        </div>
      </div>
    </>
    }
  </ExpandableFileForm>
}
