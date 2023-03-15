import React from 'react'


import Select from '~/lib/InstrumentedSelect'
import { FileTypeExtensions, validateFile } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import { faQuestionCircle } from '@fortawesome/free-solid-svg-icons'
import { OverlayTrigger, Popover } from 'react-bootstrap'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'


const allowedFileExts = FileTypeExtensions.plainText
const requiredFields = [{ label: 'Name', propertyName: 'name' }]

/** renders a form for editing/uploading a single cluster file */
export default function ClusteringFileForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  associatedClusterFileOptions=[],
  updateCorrespondingClusters,
  bucketName,
  isInitiallyExpanded,
  isAnnDataExperience
}) {
  const spatialClusterAssocs = file.spatial_cluster_associations
    .map(id => associatedClusterFileOptions.find(opt => opt.value === id))

  const validationMessages = validateFile({
    file, allFiles, allowedFileExts, requiredFields
  })


  /** create the tooltip and message for the .obsm key name section */
  function ObsmKeyNameMessage() {
    const obsmKeyNameToolTip = <span>
      <OverlayTrigger
        trigger={['hover', 'focus']}
        rootClose placement="top"
        overlay={ObsmKeyNameHelpContent()}>
        <span> .obsm key name <FontAwesomeIcon icon={faQuestionCircle}/></span>
      </OverlayTrigger>
    </span>

    return <span >
      {obsmKeyNameToolTip}
    </span>
  }

  /** gets the popup message to describe .obsm keys */
  function ObsmKeyNameHelpContent() {
    return <Popover id="cluster-obsm-key-name-popover" className="tooltip-wide">
      <div> Multi-dimensional observations annotations .obsm (attribute) key names for clusterings </div>
    </Popover>
  }

  /**
   * Configure the appropriate name form fields for Classic or AnnData upload experience
   */
  function nameFields(isAnnDataExperience) {
    if (isAnnDataExperience) {
      return <div className="row">
        <div className="col-md-6">
          <TextFormField label="Name" fieldName="name" file={file} updateFile={updateFile}/>
        </div>
        <div className="col-md-6">
          <TextFormField label= {ObsmKeyNameMessage()} fieldName="obsm_key_name" file={file}
            updateFile={updateFile} placeholderText='E.g. "x_tsne"'/>
        </div>
      </div>
    } else {
      return <TextFormField label="Name" fieldName="name" file={file} updateFile={updateFile}/>
    }
  }

  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    {nameFields(isAnnDataExperience)}
    { (file.is_spatial && !isAnnDataExperience) &&
      <div className="form-group">
        <label className="labeled-select">Corresponding clusters
          <Select options={associatedClusterFileOptions}
            data-analytics-name="spatial-associated-clusters"
            value={spatialClusterAssocs}
            isMulti={true}
            placeholder="None"
            onChange={val => updateCorrespondingClusters(file, val)}/>
        </label>
      </div>
    }
    <TextFormField label="Description / Figure legend (this will be displayed below cluster)"
      fieldName="description" file={file} updateFile={updateFile}/>

    <div className="row">
      <div className="col-md-4">
        <TextFormField label="X axis label" fieldName="x_axis_label" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-4">
        <TextFormField label="Y axis label" fieldName="y_axis_label" file={file} updateFile={updateFile}/>
      </div>
    </div>
    <div className="row">
      <div className="col-md-2">
        <TextFormField label="X domain min" fieldName="x_axis_min" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-2">
        <TextFormField label="X domain max" fieldName="x_axis_max" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-2">
        <TextFormField label="Y domain min" fieldName="y_axis_min" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-2">
        <TextFormField label="Y domain max" fieldName="y_axis_max" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-2">
        <TextFormField label="Z domain min" fieldName="z_axis_min" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-2">
        <TextFormField label="Z domain max" fieldName="z_axis_max" file={file} updateFile={updateFile}/>
      </div>
    </div>
    <div className="row">
      <div className="col-md-4">
        <TextFormField label="External link URL" fieldName="external_link_url" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-4">
        <TextFormField label="External link title" fieldName="external_link_title" file={file} updateFile={updateFile}/>
      </div>
      <div className="col-md-4">
        <TextFormField label="External link description (used as tooltip)" fieldName="external_link_description" file={file} updateFile={updateFile}/>
      </div>
    </div>
  </ExpandableFileForm>
}
