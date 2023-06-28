import React from 'react'

import { FileTypeExtensions, matchingFormFiles, validateFile } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import Select from '~/lib/InstrumentedSelect'
import { clusterFileFilter } from './ClusteringStep'
import CreatableSelect from 'react-select/creatable'

const allowedFileExts = FileTypeExtensions.plainText

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
  const validationMessages = validateFile({ file, allFiles, allowedFileExts })

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
    if (annotation.scope === 'cluster' ) {
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

  /** set available annotations based off of selected cluster file */
  function setAnnotationOptions() {
    return annotationsAvailOnStudy?.filter((annot) => {
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
      <label className="labeled-select">Associated clustering file
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
  </ExpandableFileForm>
}
