import React, { useState } from 'react'
import Panel from 'react-bootstrap/lib/Panel'
import S from 'react-switch'
const Switch = S.default ? S.default : S // necessary for CJS imports.  see https://github.com/vitejs/vite/issues/2139
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faPlus, faMinus, faTimes, faListUl } from '@fortawesome/free-solid-svg-icons'
import _difference from 'lodash/difference'
import Modal from 'react-bootstrap/lib/Modal'

import { useUpdateEffect } from '~/hooks/useUpdate'
import { isUserLoggedIn } from '~/providers/UserProvider'
import { getIdentifierForAnnotation, getDefaultAnnotationForCluster } from '~/lib/cluster-utils'
import { createUserAnnotation } from '~/lib/scp-api'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import { serverErrorEnd } from '~/lib/error-utils'
import LoadingSpinner from '~/lib/LoadingSpinner'


/** A control for adding a new user-defined annotation */
function CreateAnnotation({
  isSelecting,
  setIsSelecting,
  currentPointsSelected,
  annotationList,
  setAnnotationList,
  studyAccession,
  cluster,
  annotation,
  subsample,
  updateClusterParams
}) {
  const [showControl, setShowControl] = useState(false)
  const [isLoading, setIsLoading] = useState(!annotationList)
  const [userLabels, setUserLabels] = useState([])
  const [annotationName, setAnnotationName] = useState('')
  const [plotlyTarget, setPlotlyTarget] = useState(null)
  const [showResponseModal, setShowResponseModal] = useState(false)
  const [responseModalContent, setResponseModalContent] = useState({})

  const messages = validationMessages(userLabels, annotationName, annotationList ? annotationList.annotations : {})
  const isCreateEnabled = messages.length === 0

  /** handle the user updating the name of one of the annotations */
  function setLabelName(name, annotIndex) {
    const newUserAnnots = userLabels.map((annot, index) => {
      return {
        name: index === annotIndex ? name : annot.name,
        cells: annot.cells,
        isRemainder: annot.isRemainder,
        count: annot.count
      }
    })
    setUserLabels(newUserAnnots)
  }

  /** user cancels creating an annotation */
  function handleCancel() {
    setUserLabels([])
    setAnnotationName('')
    handlePanelToggle()
  }

  /** renders an appropriate modal and updates the cluster params with the response from the server */
  function handleCreateResponse({ message, annotations, newAnnotations, error }) {
    if (!error) {
      setResponseModalContent({
        message: `User Annotation: ${annotationName} successfully saved`,
        footer: 'You can now view this annotation via the "Annotations" dropdown.'
      })
      setAnnotationList({ ...annotationList, annotations: newAnnotations })
      const newAnnotation = newAnnotations.find(a => a.name === annotationName && a.scope === 'user')
      updateClusterParams({ // set the user-created annotation as the currently selected one
        annotation: {
          name: newAnnotation.id,
          type: 'group',
          scope: 'user'
        },
        cluster,
        subsample
      })
    } else {
      setResponseModalContent({
        message: error.message,
        footer: serverErrorEnd
      })
    }
    setShowResponseModal(true)
    setUserLabels([])
    setAnnotationName('')
    setIsSelecting(false)
    setShowControl(false)
    setIsLoading(false)
  }

  /** handles user presses create -- so the labels have already been validated for submission */
  function handleCreate() {
    const selectionPayload = {}
    userLabels.forEach((selection, index) => {
      selectionPayload[index] = {
        name: selection.name,
        values: selection.cells.join(',')
      }
    })
    let attachedAnnotation = annotation
    if (attachedAnnotation.scope === 'user') {
      // user annotations have to be bound to a non-user created annotation, so if the current shown
      // annotation is a user-defined one, attach this to the cluster default instead
      attachedAnnotation = getDefaultAnnotationForCluster(annotationList, cluster)
    }
    setIsLoading(true)
    createUserAnnotation(
      studyAccession,
      cluster,
      getIdentifierForAnnotation(attachedAnnotation),
      subsample,
      annotationName,
      selectionPayload
    ).then(handleCreateResponse).catch(error => {
      handleCreateResponse({ error })
    })
  }

  /** creates a new label entry for the given cell names */
  function addNewLabel(cellNames, allTraces) {
    if (cellNames.length) {
      let newUserLabels = userLabels.slice()
      if (newUserLabels.length < 1) {
        newUserLabels.push(computeRemainderLabel(allTraces))
      }
      const newAnnot = {
        name: '',
        cells: cellNames
      }
      // update previous selections to make sure they don't include duplicate cell names
      newUserLabels = newUserLabels.map(annot => {
        return {
          name: annot.name,
          cells: _difference(annot.cells, cellNames),
          isRemainder: annot.isRemainder
        }
      })
      newUserLabels.unshift(newAnnot)
      setUserLabels(newUserLabels)
    }
  }

  /** handle expand/collapse of the controls */
  function handlePanelToggle() {
    if (showControl) {
      setIsSelecting(false)
    } else {
      setIsSelecting(true)
    }
    setShowControl(!showControl)
  }

  /** handle deletion of a label */
  function handleDelete(deleteIndex) {
    if (userLabels.length === 2) {
      // use is deleting the only annotation they've made so far (there exist only that and the remainder)
      setUserLabels([])
    } else {
      // build new array of non-deleted labels, and without the 'remainder' label
      const newUserAnnots = userLabels.filter((annot, index) => index != deleteIndex && !annot.isRemainder)
      newUserAnnots.push(computeRemainderLabel(newUserAnnots, plotlyTarget.data))
      setUserLabels(newUserAnnots)
    }
  }

  useUpdateEffect(() => {
    const target = currentPointsSelected.target
    const selectedCells = getSelectedCells(target)
    addNewLabel(selectedCells, target.data)
    setPlotlyTarget(target)
  }, [currentPointsSelected])


  return (
    <div className="create-annotation-control">
      {!isLoading && !isUserLoggedIn() && <CreateAnnotationButton/>}
      {!isLoading && isUserLoggedIn() && <CreateAnnotationButton expanded={showControl} onClick={handlePanelToggle} />}

      <Panel className="create-annotation" expanded={showControl} onToggle={handlePanelToggle}>
        <Panel.Collapse>
          <Panel.Body>
            { isLoading && <LoadingSpinner/> }
            { !isLoading &&
              <>
                <input
                  type="text"
                  value={annotationName}
                  placeholder="Name this annotation"
                  onChange={event => setAnnotationName(event.target.value)}/>
                <label htmlFor="annotation-select-cells">Selecting Cells
                  <Switch
                    checked={isSelecting}
                    onChange={selected => setIsSelecting(selected)}
                    className="react-switch"
                    height={20}
                    id="annotation-select-cells"/>
                </label>

                { userLabels.map((annotation, index) => {
                  return <UserLabelInput
                    key={index}
                    annotation={annotation}
                    index={index}
                    setName={setLabelName}
                    deleteLabel={handleDelete}/>
                })}
                <ul className="detail">
                  {messages.map((msg, index) => <li key={index}>{msg}</li>)}
                </ul>
                <div>
                  <button
                    className="btn btn-primary"
                    disabled={!isCreateEnabled}
                    aria-disabled={!isCreateEnabled}
                    data-analytics-name="create-annotation-create"
                    onClick={handleCreate}>Create</button>
                  &nbsp;
                  <button
                    className="btn btn-secondary"
                    data-analytics-name="create-annotation-cancel"
                    onClick={handleCancel}>Cancel
                  </button>
                </div>
                <br/>
                <a className="action" href="/single_cell/user_annotations" target="_blank" data-toggle="tooltip"
                  title="manage all your created annotations">
                  <FontAwesomeIcon icon={faListUl}/> Manage all
                </a>
              </>
            }
          </Panel.Body>
        </Panel.Collapse>
      </Panel>
      <Modal
        show={showResponseModal}
        onHide={() => setShowResponseModal(false)}
        animation={false}>
        <Modal.Body className="">
          { responseModalContent.message }
          <br/><br/>
          { responseModalContent.footer }
        </Modal.Body>
        <Modal.Footer>
          <button className="btn btn-md btn-primary" onClick={() => {
            setShowResponseModal(false)
          }}>OK</button>
        </Modal.Footer>
      </Modal>
    </div>
  )
}

const CreateAnnotationControl = withErrorBoundary(CreateAnnotation)
export default CreateAnnotationControl

/** component for input of an annotation grouping */
function UserLabelInput({ annotation, index, setName, deleteLabel }) {
  let labelText = ''
  if (annotation.isRemainder) {
    labelText = `Unselected: ${annotation.cells.length} cells`
  } else {
    labelText = `Selection ${index}: ${annotation.cells.length} cells`
  }
  /** handle text change from the input */
  function updateName(event) {
    setName(event.target.value, index)
  }

  return (
    <div>
      <label htmlFor={`annotation-label-input-${index}`}>
        <span>{labelText}</span>
      </label>
      <div className="flexbox">
        <input
          id={`annotation-label-input-${index}`}
          type="text"
          value={annotation.name}
          placeholder="label these cells"
          onChange={updateName}/>
        { !annotation.isRemainder &&
          <button onClick={() => deleteLabel(index)}
            className="delete-icon"
            data-analytics-name="user-annotation-delete-label"
            title="delete this label">
            <FontAwesomeIcon icon={faTimes}/>
          </button> }
      </div>
    </div>
  )
}

/** takes in an element with a plotly graph and returns an array of selected cell names */
function getSelectedCells(plotlyTarget) {
  const selectedPoints = []
  plotlyTarget.data.forEach(trace => {
    if (trace.selectedpoints) {
      const selections = trace.selectedpoints.map(pointIndex => {
        return trace.cells[pointIndex]
      })
      // push/apply has better performance than concat, apparently
      // https://codeburst.io/jsnoob-push-vs-concat-basics-and-performance-comparison-7a4b55242fa9
      Array.prototype.push.apply(selectedPoints, selections)
    }
  })
  return selectedPoints
}

/** makes a 'remainder' annotation label that initially contains all cells */
function computeRemainderLabel(allTraces) {
  const cells = allTraces.map(trace => trace.cells).flat()
  return {
    name: '',
    isRemainder: true,
    cells
  }
}

/** returns a list of validation messages.  If empty, the submission is valid */
function validationMessages(userLabels, annotationName, annotations) {
  const msgs = []
  if (userLabels.length < 2) {
    msgs.push('Drag on a scatter plot to select a group of cells.')
    // don't clutter with extra messages if they haven't done anything yet
    return msgs
  }
  if (userLabels.some(annot => annot.name.length < 1)) {
    msgs.push('Label all selections.')
  }
  if (userLabels.some(annot => annot.name === 'Undefined')) {
    msgs.push('"Undefined" may not be used as a label.')
  }
  if (annotationName.length < 1) {
    msgs.push('Enter a name for this annotation')
  }
  const existingAnnotNames = annotations.map(annot => annot.name)
  if (existingAnnotNames.includes(annotationName)) {
    msgs.push(`${annotationName} already exists. Select a different name.`)
  }
  return msgs
}

/** Component for the button for creating an annotiation  */
function CreateAnnotationButton({ expanded = false, ...props }) {
  const iconShape = expanded ? faMinus :faPlus
  const buttonClass = expanded ? 'action-minus' : 'action-plus'

  const toolTipchoice = () => {
    if (!isUserLoggedIn()) {
      return 'You must sign in to create custom annotations'
    } else {
      if (expanded) {
        return 'Explore existing annotations'
      } else {
        return 'Create custom annotations'
      }
    }
  }

  return <button className = {buttonClass}
    data-analytics-name = {!isUserLoggedIn() ? 'toggle-create-annotation-signedout' :'toggle-create-annotation'}
    data-toggle="tooltip"
    aria-label="Add annotation"
    data-original-title = {toolTipchoice()} // necessary to dynamically update the tooltip text
    {...props}>
    <FontAwesomeIcon icon={iconShape}/> &nbsp;
  </button>
}
