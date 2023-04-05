import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faChevronDown, faChevronUp, faCheck, faQuestionCircle, faLink } from '@fortawesome/free-solid-svg-icons'

import StepTabHeader from './StepTabHeader'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import { OverlayTrigger, Popover } from 'react-bootstrap'
import { clusterFileFilter } from './ClusteringStep'
import { metadataFileFilter } from './MetadataStep'
import { processedFileFilter } from './ProcessedExpressionStep'
import LoadingSpinner from '~/lib/LoadingSpinner'


/** renders a list of the steps and summary study information */
function RawWizardNavPanel({
  formState, serverState, currentStep, setCurrentStep, studyAccession, steps, studyName,
  mainSteps, supplementalSteps, nonVizSteps, isAnnDataExperience
}) {
  const [othersExpanded, setOthersExpanded] = useState(true)
  const [supplementalExpanded, setSupplementalExpanded] = useState(true)
  const [annDataMainExpanded, setAnnDataMainExpanded] = useState(true)

  const expansionIcon = othersExpanded ? faChevronUp : faChevronDown
  const expansionIcon2 = supplementalExpanded ? faChevronUp : faChevronDown
  const expansionIcon3 = annDataMainExpanded ? faChevronUp : faChevronDown


  return <div className="wizard-side-panel">
    {MainStepsDisplay(
      formState, serverState, currentStep, setCurrentStep, mainSteps, isAnnDataExperience,
      annDataMainExpanded, setAnnDataMainExpanded, expansionIcon3
    )}
    <ul className="upload-wizard-steps" role="tablist" data-analytics-name="upload-wizard-secondary-steps">
      <li className="other-header" role="tab" >
        <button className="list-link" onClick={() => setOthersExpanded(!othersExpanded)} >
          <span className="step-number">
            <span className="badge highlight">+</span>
          </span>
          <span>
            <a className="action link" role="link">
            Other files <FontAwesomeIcon icon={expansionIcon}/>
            </a>
          </span>
        </button>
      </li>
      { othersExpanded && supplementalSteps.map((step, index) =>
        <StepTabHeader key={index}
          step={step}
          index={index}
          showIndex={false}
          formState={formState}
          serverState={serverState}
          currentStep={currentStep}
          setCurrentStep={setCurrentStep}/>) }
    </ul>
    <ul className="upload-wizard-steps" role="tablist" data-analytics-name="upload-wizard-tertiary-steps">
      <li className="other-header" role="tab" >
        <button className="list-link" onClick={() => setSupplementalExpanded(!supplementalExpanded)} >
          <span className="step-number">
            <span className="badge highlight">+</span>
          </span>
          <span>
            <a className="action link" role="link">
              <NonVizHelpMessage/> <FontAwesomeIcon icon={expansionIcon2}/>
            </a>
          </span>
        </button>
      </li>
      { supplementalExpanded && nonVizSteps.map((step, index) =>
        <StepTabHeader key={index}
          step={step}
          index={index}
          showIndex={false}
          formState={formState}
          serverState={serverState}
          currentStep={currentStep}
          setCurrentStep={setCurrentStep}/>) }

    </ul>
    { isAnnDataExperience && <span className='margin-left-extra'>
      <a href="https://forms.gle/dRUVSh7WAz9Dh6Ag8" target="_blank" title="Take a brief survey on AnnData data upload">
        Provide feedback <FontAwesomeIcon icon={faLink}/>
      </a>
    </span>}
  </div>
}

/** create the tooltip and message for the non-visualizable files section */
function NonVizHelpMessage() {
  const notVizToolTip = <span>
    <OverlayTrigger
      trigger={['hover', 'focus']}
      rootClose placement="top"
      overlay={nonVizHelpContent()}>
      <span> Non-visualized files <FontAwesomeIcon icon={faQuestionCircle}/></span>
    </OverlayTrigger>
  </span>

  return <span >
    {notVizToolTip}
  </span>
}

/** gets the popup message based on whether there are files parsing */
function nonVizHelpContent() {
  return <Popover id="cluster-viz-upload-info" className="tooltip-wide">
    <div>These files will not be part of the visualization in the Explore tab.
      They should only be added as supplemental items that would be useful for download.
    </div>
  </Popover>
}

/** gets the popup message to describe .obsm keys */
function annDataUploadInfoContent() {
  return <Popover id="anndata-upload-info-popover" className="tooltip-wide">
    <div>
      AnnData upload requires you to fill out the necessary information in the tabs for `&quot;`Expression matrices`&quot;` and `&quot;`Clustering`&quot;`.
      You will then upload the single AnnData file in the AnnData tab.
    </div>
  </Popover>
}

/** create the tooltip and message for the AnnData section */
function AnnDataHelpMessage() {
  const annDataInfoToolTip = <span>
    <OverlayTrigger
      trigger={['hover', 'focus']}
      rootClose placement="right"
      overlay={annDataUploadInfoContent()}>
      <span>  <FontAwesomeIcon icon={faQuestionCircle}/></span>
    </OverlayTrigger>
  </span>

  return <span >
    {annDataInfoToolTip}
  </span>
}

/** shows current expression and clustering visualization status */
function VisualizationStatuses({ serverState }) {
  if (!serverState) {
    return <></>
  }
  const metadataFiles = serverState.files.filter(metadataFileFilter)
  const isMetadataParsing = metadataFiles.some(f => f.parse_status === 'parsing')
  const isMetadataParsed = metadataFiles.some(f => f.parse_status === 'parsed')

  const clusteringFiles = serverState.files.filter(clusterFileFilter)
  const isClusteringParsing = isMetadataParsing || clusteringFiles.some(f => f.parse_status === 'parsing')
  const isClusteringParsed = isMetadataParsed && clusteringFiles.some(f => f.parse_status === 'parsed')

  const processedExpFiles = serverState.files.filter(processedFileFilter)
  const isExpressionParsing = isMetadataParsing || processedExpFiles.some(f => f.parse_status === 'parsing')
  const isExpressionParsed = isMetadataParsed && isClusteringParsed && processedExpFiles.some(f => f.parse_status === 'parsed')

  let clusterStatusMsg = <span className="success">Clustering visuals <FontAwesomeIcon icon={faCheck}/></span>
  if (!isClusteringParsed) {
    clusterStatusMsg = <span className="warning">No clustering visuals <FontAwesomeIcon icon={faQuestionCircle}/></span>
  }
  const clusterVizIndicator = <div>
    <OverlayTrigger
      trigger={['hover', 'focus']}
      rootClose placement="top"
      overlay={clusteringHelpContent(isClusteringParsing)}>
      <span>
        {clusterStatusMsg} { isClusteringParsing && <LoadingSpinner/> }
      </span>
    </OverlayTrigger>
  </div>

  let expressionStatusMsg = <span className="success">Expression visuals <FontAwesomeIcon icon={faCheck}/></span>
  if (!isExpressionParsed) {
    expressionStatusMsg = <span className="warning">No expression visuals <FontAwesomeIcon icon={faQuestionCircle}/></span>
  }
  const expressionVizIndicator = <div>
    <OverlayTrigger
      trigger={['hover', 'focus']}
      rootClose placement="top"
      overlay={expressionHelpContent(isExpressionParsing)}>
      <span>
        {expressionStatusMsg} { isExpressionParsing && <LoadingSpinner/> }
      </span>
    </OverlayTrigger>
  </div>
  return <div className="viz-notifications">
    {clusterVizIndicator}
    {expressionVizIndicator}
  </div>
}

/** gets the popup message based on whether there are files parsing */
function expressionHelpContent(isExpressionParsing) {
  return <Popover id="expression-viz-upload-info" className="tooltip-wide">
    <div>
      A processed matrix file, metadata file, and clustering file are required for gene expression visualization.
    </div>
    { isExpressionParsing && parsingMessage }
  </Popover>
}

/** gets the popup message based on whether there are files parsing */
function clusteringHelpContent(isClusteringParsing) {
  return <Popover id="cluster-viz-upload-info" className="tooltip-wide">
    <div>A metadata file and clustering file are required for cluster visualization.</div>
    { isClusteringParsing && parsingMessage }
  </Popover>
}

/**
 * Return the appropriate display of the main steps based on classic or AnnData upload experience
 */
function MainStepsDisplay(formState, serverState, currentStep, setCurrentStep, mainSteps,
  isAnnDataExperience, annDataMainExpanded, setAnnDataMainExpanded, expansionIcon) {
  if (isAnnDataExperience) {
    return <ul className="upload-wizard-steps" role="tablist" data-analytics-name="upload-wizard-anndata-main-steps">
      <li className="other-header" role="tab" >
        <button className="list-link" onClick={() => setAnnDataMainExpanded(!annDataMainExpanded)} >
          <span className="step-number">
            <span className="badge highlight">+</span>
          </span>
          <span>
            <a className="action link" role="link">
            AnnData <sup>BETA</sup> <AnnDataHelpMessage/> <FontAwesomeIcon icon={expansionIcon}/>
            </a>
          </span>
        </button>
      </li>
      {annDataMainExpanded && mainSteps.map((step, index) =>
        <StepTabHeader key={index}
          step={step}
          index={index}
          showIndex={false}
          formState={formState}
          serverState={serverState}
          currentStep={currentStep}
          setCurrentStep={setCurrentStep}/>) }
    </ul>
  } else {
    return <span>
      <ul className="upload-wizard-steps" role="tablist" data-analytics-name="upload-wizard-main-steps">
        { mainSteps.map((step, index) =>
          <StepTabHeader key={index}
            step={step}
            index={index}
            formState={formState}
            serverState={serverState}
            currentStep={currentStep}
            setCurrentStep={setCurrentStep}/>) }
      </ul>
      <VisualizationStatuses serverState={serverState}/>
    </span>
  }
}

const parsingMessage = <div>Some files that will impact visualization are being processed.</div>

const WizardNavPanel = withErrorBoundary(RawWizardNavPanel)
export default WizardNavPanel
