import React from 'react'

import { FileTypeExtensions, matchingFormFiles, validateFile } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import Select from '~/lib/InstrumentedSelect'
import { clusterFileFilter } from './ClusteringStep'
import { differentialExpressionFileFilter } from './DifferentialExpressionStep'
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
    opt => opt.value === file.differential_expression_file_info.clustering_association?.id
  )

  const annotsAlreadyInUse = []
  // retrieve the annotations that are already in use on a DE file
  allFiles.filter(differentialExpressionFileFilter).filter(
    diffExpFile => diffExpFile.differential_expression_file_info.annotation_association?.length > 0
  ).forEach(file => {
    annotsAlreadyInUse.push(file.differential_expression_file_info.annotation_association[0])
  })

  // filter down the annotations to only allow choosing an annotation that hasn't been chosen already
  // each annotation is allowed to be associated with only one DE file
  const annotationOptions = annotationsAvailOnStudy?.map(
    cf => ({ label: cf.name, value: cf.name })
  ).filter(
    annotObj => !annotsAlreadyInUse.includes(annotObj.value)
  )

  const associatedAnnotation = annotationOptions?.find(
    opt => opt.value === file.differential_expression_file_info.annotation_association?.name
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
    opt => opt.value === file.differential_expression_file_info.comp_method_association?.name
  )

  /** handle a change in the associated cluster select */
  function updateAssociatedCluster(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { clustering_association: newVal } })
  }

  /** handle a change in the associated annotation select */
  function updateAssociatedAnnotation(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { annotation_association: newVal } })
  }

  /** handle a change in the associated computational method select */
  function updateAssociatedCompMethod(file, option) {
    let newVal = null
    if (option) {
      newVal = option.value
    }
    updateFile(file._id, { differential_expression_file_info: { comp_method_association: newVal } })
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
