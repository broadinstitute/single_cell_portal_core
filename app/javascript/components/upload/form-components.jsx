import React, { useState } from 'react'
import Modal from 'react-bootstrap/lib/Modal'
import { Popover, OverlayTrigger } from 'react-bootstrap'

import LoadingSpinner from '~/lib/LoadingSpinner'

/** renders a 'Add File' button that occupies a full row */
export function AddFileButton({ newFileTemplate, addNewFile, text='Add file' }) {
  return <div className="row top-margin">
    <div className="col-md-12">
      <button className="btn btn-secondary terra-secondary-btn" onClick={() => addNewFile(newFileTemplate, true)}>
        <span className="fas fa-plus"></span> {text}
      </button>
    </div>
  </div>
}

/** renders a basic label->value text field in a bootstrap form control */
export function TextFormField({ label, fieldName, file, updateFile, placeholderText='' }) {
  const fieldId = `${fieldName}-input-${file._id}`
  let value = file[fieldName] ?? ''
  const [objName, nestedPropName] = fieldName.split('.')
  if (nestedPropName) {
    // handle a nested property like 'heatmap_file_info.custom_scaling'
    value = file[objName][nestedPropName] ?? ''
  }
  return <div className="form-group">
    <label htmlFor={fieldId}>{label}</label><br/>
    <input className="form-control"
      type="text"
      id={fieldId}
      value={value}
      placeholder={placeholderText}
      onChange={event => {
        const update = {}
        if (nestedPropName) {
          // handle a nested property like 'heatmap_file_info.custom_scaling'
          update[objName] = {}
          update[objName][nestedPropName] = event.target.value
        } else {
          update[fieldName] = event.target.value
        }
        updateFile(file._id, update)
      }}/>
  </div>
}

/** renders save and delete buttons for a given file */
export function SaveDeleteButtons({ file, updateFile, saveFile, deleteFile, validationMessages={} }) {
  const [showConfirmDeleteModal, setShowConfirmDeleteModal] = useState(false)

  /** delete file with/without confirmation dialog as appropriate */
  function handleDeletePress() {
    if (file.status === 'new') {
      // it hasn't been uploaded yet, just delete it
      deleteFile(file)
    } else {
      setShowConfirmDeleteModal(true)
    }
  }

  const saveDisabled = Object.keys(validationMessages).length > 0
  let saveButton = <button
    style={{ pointerEvents: saveDisabled ? 'none' : 'auto' }}
    type="button"
    className={file.isDirty ? 'btn btn-primary margin-right' : 'btn terra-secondary-btn margin-right'}
    onClick={() => saveFile(file)}
    disabled={saveDisabled}
    aria-disabled={saveDisabled}
    data-testid="file-save">
    Save { file.uploadSelection && <span>&amp; Upload</span> }
  </button>

  if (saveDisabled) {
    // if saving is disabled, wrap the disabled button in a popover that will show the errors
    const validationPopup = <Popover id={`save-invalid-${file._id}`} className="tooltip-wide">
      { Object.keys(validationMessages).map(key => <div key={key}>{validationMessages[key]}</div>) }
    </Popover>
    saveButton = <OverlayTrigger trigger={['hover', 'focus']} rootClose placement="top" overlay={validationPopup}>
      <div>{ saveButton }</div>
    </OverlayTrigger>
  } else if (file.isSaving) {
    const savingText = file.saveProgress ? <span>Uploading {file.saveProgress}% </span> : 'Saving'
    saveButton = <button type="button"
      className="btn btn-primary margin-right">
      {savingText} <LoadingSpinner testId="file-save-spinner"/>
    </button>
  }

  return <div className="flexbox button-panel">
    { saveButton }
    <button type="button" className="btn terra-secondary-btn" onClick={handleDeletePress} data-testid="file-delete">
      Delete
    </button>
    <Modal
      show={showConfirmDeleteModal}
      onHide={() => setShowConfirmDeleteModal(false)}
      animation={false}>
      <Modal.Body className="">
        Are you sure you want to delete { file.name }?<br/>
        <span>The file will be removed from the workspace and all corresponding database records deleted.</span>
      </Modal.Body>
      <Modal.Footer>
        <button className="btn btn-md btn-primary" onClick={() => {
          deleteFile(file)
          setShowConfirmDeleteModal(false)
        }}>Delete</button>
        <button className="btn btn-md terra-secondary-btn" onClick={() => {
          setShowConfirmDeleteModal(false)
        }}>Cancel</button>
      </Modal.Footer>
    </Modal>
  </div>
}

/** renders the note that AnnData upload will occur later for preceeding upload steps */
export function AnnDataPreUploadDirections() {
  return <>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
        Fill in data here, the file upload will occur in the AnnData tab.
        </p>
      </div>
    </div></>
}
