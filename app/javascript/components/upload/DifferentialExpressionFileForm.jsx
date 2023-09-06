import React from 'react'

import { FileTypeExtensions, matchingFormFiles, validateFile } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import Select from '~/lib/InstrumentedSelect'
import { clusterFileFilter } from './ClusteringStep'
import CreatableSelect from 'react-select/creatable'

const allowedFileExts = FileTypeExtensions.plainText
const requiredFields = [
  { label: 'Associated annotation', propertyName: 'differential_expression_file_info.annotation_name' },
  { label: 'Associated clustering file', propertyName: 'differential_expression_file_info.clustering_association' }
]

/**
 * Get Select option groups "Inferred options" and "Other options"
 *
 * @param metricType {String} either "sizes" or "significances"
 * @param notes {Object} arrays of inferred metrics from raw file, by metric type
 * @param file {Object} study file object (not raw file)
 */
function inferOptions(metricType, notes, file) {
  const inferredMetrics =
    notes[metricType].map(opt => ({ label: opt, value: opt }))
  const otherMetrics =
    notes.metrics.filter(m => !notes[metricType].includes(m))
      .map(opt => ({ label: opt, value: opt }))

  const options = [
    { 'label': 'Inferred options', 'options': inferredMetrics },
    { 'label': 'Other options', 'options': otherMetrics }
  ]

  // E.g. significances -> significance_metric
  const snakeCaseMetricType = `${metricType.slice(0, -1)}_metric`

  // Determine default value for select
  const allMetrics = inferredMetrics.concat(otherMetrics)
  const metric = allMetrics.find(
    opt => opt.value === file.differential_expression_file_info[snakeCaseMetricType]
  ) || { label: notes[metricType][0], value: notes[metricType][0] }

  return [options, metric]
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

  const notes = file.notes

  const [sizeMetricOptions, sizeMetric] =
    notes ? inferOptions('sizes', notes, file) : [[], null]
  const [significanceMetricOptions, significanceMetric] =
    notes ? inferOptions('significances', notes, file) : [[], null]

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

  /** handle a change in the "Size metric" select */
  function updateSizeMetric(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { size_metric: newVal } })
  }

  /** handle a change in the "Significance metric" select */
  function updateSignificanceMetric(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { significance_metric: newVal } })
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

  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
    <div className="form-group">
      <label className="labeled-select">Associated clustering
        <Select options={clusterFileOptions}
          data-analytics-name="differential-expression-associated-cluster-select"
          value={associatedCluster}
          placeholder="Select one..."
          onChange={val => updateAssociatedCluster(file, val)}/>
      </label>
    </div>
    <div className="form-group">
      <label className="labeled-select">Associated annotation
        <Select options={annotationOptions}
          data-analytics-name="differential-expression-associated-annotation-select"
          value={associatedAnnotation}
          placeholder="Select one..."
          onChange={val => updateAssociatedAnnotation(file, val)}/>
      </label>
    </div>
    <div className="form-group">
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
    {file.notes &&
    <div className="row">
      <div className="form-group col-md-3">
        <label className="labeled-select">Size metric
          <Select
            data-analytics-name="differential-expression-size-metric-select"
            options={sizeMetricOptions}
            defaultValue={sizeMetric}
            value={sizeMetric}
            className="labeled-select"
            onChange={val => updateSizeMetric(file, val)}
            placeholder="Select metric for DE size"
          />
        </label>
      </div>
      <div className="form-group col-md-3">
        <label className="labeled-select">Significance metric
          <Select
            data-analytics-name="differential-expression-significance-metric-select"
            options={significanceMetricOptions}
            defaultValue={significanceMetric}
            value={significanceMetric}
            className="labeled-select"
            onChange={val => updateSignificanceMetric(file, val)}
            placeholder="Select metric for DE significance"
          />
        </label>
      </div>
    </div>
    }
  </ExpandableFileForm>
}
