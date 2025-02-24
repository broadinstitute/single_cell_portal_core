/** Ensure a name is provided for the study */
function validateName(input) {
  const issues = []

  const name = input.value
  if (name === '') {
    const msg = 'Enter a name for your study.'
    issues.push(['error', 'missing-name', msg])
  }

  return issues
}

/** Convert Date string to string format in "Data release date" UI */
function dateToMMDDYYYY(dateString) {
  const date = new Date(dateString)
  const rawMonth = date.getMonth() + 1; // Months are zero-indexed, so add 1
  const rawDay = date.getDate();
  const year = date.getFullYear();

  const month = rawMonth.toString().padStart(2, '0');
  const day = rawDay.toString().padStart(2, '0');

  const MMDDYYYY = `${month}/${day}/${year}`;

  return MMDDYYYY
}

/** Ensure any embargo date is between tomorrow and max embargo date */
export function validateEmbargo(embargoInput) {
  const issues = []

  const rawEmbargoDate = embargoInput.value
  const embargoDate = new Date(embargoInput.value)
  const maxDate = new Date(embargoInput.max)

  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);

  if (
    rawEmbargoDate !== '' &&
    (embargoDate > maxDate || embargoDate < tomorrow)
  ) {
    const tomorrowFormatted = dateToMMDDYYYY(tomorrow)
    const maxDateFormatted = dateToMMDDYYYY(maxDate)

    const msg =
      `If embargoed, date must be between ` +
      `tomorrow (${tomorrowFormatted}) and ${maxDateFormatted}.`

    issues.push(['error', 'invalid-embargo', msg])
  }

  return issues
}

/** Ensure a billing project is selected */
function validateBillingProject(input) {
  const issues = []

  const billingProject = input.value
  if (billingProject === '') {
    const msg = 'Pick a billing project from above menu.'
    issues.push(['error', 'missing-billing-project', msg])
  }

  return issues
}

/** Ensure a workspace is selected, if using existing workspace */
function validateWorkspace(input, studyForm) {
  const issues = []

  const workspace = input.value
  const useExistingWorkspace =
    studyForm.querySelector('#study_use_existing_workspace').value === '1'

  if (useExistingWorkspace && workspace === '') {
    const msg = 'Enter a workspace name, or set "Use existing workspace?" to "No".'
    issues.push(['error', 'missing-workspace', msg])
  }

  return issues
}

/** Add or remove error classes from field elements around given element */
function updateErrorState(element, addOrRemove) {
  const fieldDiv = element.closest('[class^="col-md"]')

  if (addOrRemove === 'add') {
    fieldDiv.querySelector('label').classList.add('text-danger')
    fieldDiv.classList.add('has-error', 'has-feedback')
  } else {
    fieldDiv.querySelector('label').classList.remove('text-danger')
    fieldDiv.classList.remove('has-error', 'has-feedback')
  }
}

/** Render messages for any validation issue for given input element */
function writeValidationMessage(input, issues) {
  if (issues.length === 0) {return}

  // Consider below if we need to deal with multiple errors per field
  // See ValidationMessage.jsx for model to follow
  // const messageList = '<ul>' + issues.map(issue => {
  //   const msg = issue[2]
  //   return `<li className="validation-error">${msg}</li>`
  // }).join('') + '</ul>

  const message = issues[0][2]

  const messageHtml = `<div class="validation-error">${message}</div>`

  updateErrorState(input, 'add')
  input.insertAdjacentHTML('afterend', messageHtml)
}

/** Validate given field, get issues, write any messages */
function checkField(studyForm, field, validateFns, issues) {
  const input = studyForm.querySelector(`#study_${field}`)
  let fieldIssues
  if (field === 'firecloud_workspace') {
    fieldIssues = validateFns[field](input, studyForm)
  } else {
    fieldIssues = validateFns[field](input)
  }
  issues = issues.concat(fieldIssues)
  writeValidationMessage(input, fieldIssues)

  return issues
}

/** Validation form in "Create study" page */
export function validateStudy(studyForm) {
  let issues = []

  // Clear any prior error messages
  document.querySelectorAll('.validation-error').forEach(error => {
    updateErrorState(error, 'remove')
    error.remove()
  })

  const validateFns = {
    'name': validateName,
    'firecloud_project': validateBillingProject, // "Terra billing project"
    'embargo': validateEmbargo, // "Data release date"
    'firecloud_workspace': validateWorkspace // "Existing Terra workspace"
  }

  const fields = Object.keys(validateFns)
  fields.forEach(field => {
    issues = checkField(studyForm, field, validateFns, issues)
  })

  return issues
}
