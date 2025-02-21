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

    const message =
      `If embargoed, date must be between ` +
      `tomorrow (${tomorrowFormatted}) and ${maxDateFormatted}.`

    issues.push(['error', 'invalid-embargo', message])
  }

  return issues
}

/** Add or remove error classes from field elements around given element */
function updateErrorState(element, addOrRemove) {
  const parent = element.parentElement

  if (addOrRemove === 'add') {
    parent.querySelector('label').classList.add('text-danger')
    parent.classList.add('has-error', 'has-feedback')
  } else {
    parent.querySelector('label').classList.remove('text-danger')
    parent.classList.remove('has-error', 'has-feedback')
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

/** Validation form in "Create study" page */
export function validateStudy(studyForm) {
  let issues = []

  // Clear any prior error messages
  document.querySelectorAll('.validation-error').forEach(error => {
    updateErrorState(error, 'remove')
    error.remove()
  })

  const embargoInput = studyForm.querySelector('#study_embargo')
  const embargoIssues = validateEmbargo(embargoInput)
  issues = issues.concat(embargoIssues)
  writeValidationMessage(embargoInput, embargoIssues)

  return issues
}
