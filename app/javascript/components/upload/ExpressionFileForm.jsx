import React, { useState } from 'react'
import _kebabCase from 'lodash/kebabCase'

import Select from '~/lib/InstrumentedSelect'
import MTXBundledFilesForm from './MTXBundledFilesForm'
import { FileTypeExtensions } from './upload-utils'
import ExpandableFileForm from './ExpandableFileForm'

import { TextFormField } from './form-components'
import { findBundleChildren, validateFile } from './upload-utils'
import { faQuestionCircle } from '@fortawesome/free-solid-svg-icons'
import { OverlayTrigger, Popover } from 'react-bootstrap'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'

const REQUIRED_FIELDS = [{ label: 'species', propertyName: 'taxon_id' },
  { label: 'Biosample input type', propertyName: 'expression_file_info.biosample_input_type' },
  { label: 'Library preparation protocol', propertyName: 'expression_file_info.library_preparation_protocol' },
  { label: 'Modality', propertyName: 'expression_file_info.modality' }]
const RAW_COUNTS_REQUIRED_FIELDS = REQUIRED_FIELDS.concat([{
  label: 'units', propertyName: 'expression_file_info.units'
}])
const PROCESSED_ASSOCIATION_FIELD = [
  { label: 'Associated raw counts files', propertyName: 'expression_file_info.raw_counts_associations' }
]
const RAW_LOCATION_FIELD = [
  { label: 'Raw count data location', propertyName: 'raw_location' },
]

/** renders a form for editing/uploading an expression file (raw or processed) and any bundle children */
export default function ExpressionFileForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  addNewFile,
  fileMenuOptions,
  rawCountsOptions,
  bucketName,
  isInitiallyExpanded,
  featureFlagState,
  isAnnDataExperience
}) {
  const associatedChildren = findBundleChildren(file, allFiles)
  const speciesOptions = fileMenuOptions.species.map(spec => ({ label: spec.common_name, value: spec.id }))
  const selectedSpecies = speciesOptions.find(opt => opt.value === file.taxon_id)
  const isMtxFile = file.file_type === 'MM Coordinate Matrix'
  const rawCountsInfo = file.expression_file_info.is_raw_counts
  const isRawCountsFile = rawCountsInfo === 'true' || rawCountsInfo === true
  const [showRawCountsUnits, setShowRawCountsUnits] = useState(isRawCountsFile)

  const allowedFileExts = isMtxFile ? FileTypeExtensions.mtx : FileTypeExtensions.plainText
  let requiredFields = showRawCountsUnits ? RAW_COUNTS_REQUIRED_FIELDS : REQUIRED_FIELDS
  const rawCountsRequired = featureFlagState && featureFlagState.raw_counts_required_frontend && !isAnnDataExperience
  if (rawCountsRequired && !isRawCountsFile ) {
    requiredFields = requiredFields.concat(PROCESSED_ASSOCIATION_FIELD)
  }
  const requireLocation = (rawCountsRequired || isRawCountsFile) && isAnnDataExperience
  if (requireLocation) {
    requiredFields = requiredFields.concat(RAW_LOCATION_FIELD)
  }
  const validationMessages = validateFile({ file, allFiles, allowedFileExts, requiredFields, isAnnDataExperience })

  const associatedRawCounts = !isAnnDataExperience && file.expression_file_info.raw_counts_associations.map(id => ({
    label: rawCountsOptions.find(rf => rf.value == id)?.label,
    value: id
  }))

  function toggleIsRawCounts(rawCountsVal) {
    updateFile(file._id, { expression_file_info: {is_raw_counts: rawCountsVal} })
    setShowRawCountsUnits(rawCountsVal)
  }

  /** create the tooltip and message for the .obsm key name section */
  function rawSlotMessage() {
    const rawSlotToolTip = <span>
      <OverlayTrigger
        trigger={['hover', 'focus']}
        rootClose placement="top"
        delayHide={1500}
        overlay={rawSlotHelpContent()}>
        <span> Raw count data location * <FontAwesomeIcon icon={faQuestionCircle}/></span>
      </OverlayTrigger>
    </span>

    return <span >
      {rawSlotToolTip}
    </span>
  }

  /** gets the popup message to describe .obsm keys */
  function rawSlotHelpContent() {
    const layersLink = <a href="https://anndata.readthedocs.io/en/latest/generated/anndata.AnnData.layers.html"
                          target="_blank">layers</a>
    const rawLink = <a href="https://anndata.readthedocs.io/en/latest/generated/anndata.AnnData.raw.html"
                                target="_blank">.raw</a>
    return <Popover id="cluster-obsm-key-name-popover" className="tooltip-wide">
      <div>
        Location of raw count data in your AnnData file. This can be the raw slot ({rawLink}) or the name of a layer in
        the {layersLink} section.
      </div>
    </Popover>
  }

  return <ExpandableFileForm {...{
    file,
    allFiles,
    updateFile,
    saveFile,
    allowedFileExts,
    deleteFile,
    validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    {!isAnnDataExperience &&
    <div className="form-group">
      <label>Matrix file type:</label><br/>
      <label className="sublabel">
        <input type="radio"
          name={`exp-matrix-type-${file._id}`}
          value="false"
          checked={!isMtxFile}
          onChange={e => updateFile(file._id, { file_type: 'Expression Matrix' })} />
          &nbsp;Dense matrix
      </label>
      <label className="sublabel">
        <input type="radio"
          name={`exp-matrix-type-${file._id}`}
          value="true" checked={isMtxFile}
          onChange={e => updateFile(file._id, { file_type: 'MM Coordinate Matrix' })}/>
          &nbsp;Sparse matrix (.mtx)
      </label>
    </div>
    }
    { (!isAnnDataExperience && !isRawCountsFile) &&
      <div className="form-group">
        <label className="labeled-select">Associated raw counts files
          <Select options={rawCountsOptions}
            data-analytics-name="expression-raw-counts-select"
            value={associatedRawCounts}
            placeholder="Select one..."
            isMulti={true}
            onChange={val => updateFile(file._id, {
              expression_file_info: {
                raw_counts_associations: val ? val.map(opt => opt.value) : []
              }
            })}/>
        </label>
      </div>
    }

    <div className="form-group">
      <label className="labeled-select" data-testid="expression-select-taxon_id">Species *
        <Select options={speciesOptions}
          data-analytics-name="expression-species-select"
          value={selectedSpecies}
          placeholder="Select one..."
          onChange={val => updateFile(file._id, { taxon_id: val.value })}/>
      </label>
    </div>

    { showRawCountsUnits && !isAnnDataExperience &&
      <ExpressionFileInfoSelect label="Units *"
        propertyName="units"
        rawOptions={fileMenuOptions.units}
        file={file}
        updateFile={updateFile}/>
    }

    { isAnnDataExperience &&
      <div className="row">
        <div className="form-radio col-sm-4">
          <label className="labeled-select">I have raw count data</label>
          <label className="sublabel">
            <input type="radio"
                   name={`anndata-raw-counts-${file._id}`}
                   value="true"
                   checked={isRawCountsFile}
                   onChange={e => toggleIsRawCounts(true)}/>
            &nbsp;Yes
          </label>
          <label className="sublabel">
            <input type="radio"
                   name={`anndata-raw-counts-${file._id}`}
                   value="false"
                   checked={!isRawCountsFile}
                   onChange={e => toggleIsRawCounts(false)}/>
            &nbsp;No
          </label>
        </div>
        {requireLocation && <div className="col-sm-4">
          <TextFormField label={rawSlotMessage()}
                         fieldName="raw_location"
                         file={file}
                         updateFile={updateFile}
                         placeholderText='Specify .raw or name of layer'/></div>
        }
        { showRawCountsUnits && <div className="col-sm-4">
          <ExpressionFileInfoSelect label="Units *"
                                    propertyName="units"
                                    rawOptions={fileMenuOptions.units}
                                    file={file}
                                    updateFile={updateFile}/>
        </div>
        }
      </div>
    }

    <ExpressionFileInfoSelect label="Biosample input type *"
      propertyName="biosample_input_type"
      rawOptions={fileMenuOptions.biosample_input_type}
      file={file}
      updateFile={updateFile}/>

    <ExpressionFileInfoSelect label="Library preparation protocol *"
      propertyName="library_preparation_protocol"
      rawOptions={fileMenuOptions.library_preparation_protocol}
      file={file}
      updateFile={updateFile}/>

    <ExpressionFileInfoSelect label="Modality *"
      propertyName="modality"
      rawOptions={fileMenuOptions.modality}
      file={file}
      updateFile={updateFile}/>

    <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
    <TextFormField label="Expression axis label" fieldName="y_axis_label" file={file} updateFile={updateFile}/>

    { isMtxFile &&
      <MTXBundledFilesForm {...{
        parentFile: file, allFiles, updateFile, saveFile, deleteFile,
        addNewFile, associatedChildren, bucketName
      }}/>
    }
  </ExpandableFileForm>
}

/** render a dropdown for an expression file info property */
function ExpressionFileInfoSelect({ label, propertyName, rawOptions, file, updateFile }) {
  const selectOptions = rawOptions.map(opt => ({ label: opt, value: opt }))
  let selectedOption = selectOptions.find(opt => opt.value === file.expression_file_info[propertyName])
  // if the variable passed to 'value' in react-select is undefined, sometimes react-select will not rerender
  // this can happen if the server returns different data than was submitted by the user
  if (!selectedOption) {
    selectedOption = null
  }
  return <div className="form-group">
    <label className="labeled-select" data-testid={`expression-select-${_kebabCase(propertyName)}`}>{label}
      <Select options={selectOptions}
        data-analytics-name={`expression-select-${_kebabCase(propertyName)}`}
        value={selectedOption}
        placeholder="Select one..."
        onChange={val => {
          const expInfo = {}
          expInfo[propertyName] = val.value
          updateFile(file._id, { expression_file_info: expInfo })
        }}/>
    </label>
  </div>
}
