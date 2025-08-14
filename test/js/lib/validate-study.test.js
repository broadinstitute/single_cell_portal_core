import { validateStudy } from 'lib/validation/validate-study'

const today = new Date()
const futureDate = new Date()
futureDate.setFullYear(today.getFullYear() + 2)
const MAX_DATE = futureDate.toISOString().split('T')[0] // 2 years from today

/** Make new "Create study" form element */
function createStudyFormElement(tag, displayLabel, id, value, attrs={}) {
  const div = document.createElement('div')
  div.setAttribute('class', 'col-md-3')
  const label = document.createElement('label')
  label.setAttribute('for', id)

  // Construct core `input` or `select`
  attrs.name = `study[${id}]`
  attrs.id = `study_${id}`
  attrs.value = value
  label.innerText = displayLabel
  const element = document.createElement(tag)
  Object.entries(attrs).forEach(([attrName, attrValue]) => {
    element.setAttribute(attrName, attrValue)
  })

  div.appendChild(label)
  div.appendChild(element)

  const formElement = div

  return formElement
}

/** Create input DOM element with given attributes, and related elements */
function createInput(displayLabel, id, value, attrs={}) {
  const tag = 'input'
  const input = createStudyFormElement(tag, displayLabel, id, value, attrs)
  return input
}

/** Create text input DOM element with given attributes, and related elements */
function createTextInput(displayLabel, id, value, attrs={}) {
  attrs.type = 'text'
  const input = createInput(displayLabel, id, value, attrs)
  return input
}

/** Create select menu DOM element with given attributes, and related elements */
function createSelect(displayLabel, id, value, attrs={}) {
  const selectDiv = createStudyFormElement('select', displayLabel, id, value, attrs)
  const option = document.createElement('option')
  option.setAttribute('value', value)
  option.setAttribute('selected', 'selected')
  selectDiv.querySelector('select').appendChild(option)
  return selectDiv
}

/** Create new study form DOM elements */
function createStudyForm(
  name, isPublic, embargo
) {
  const form = document.createElement('form')

  const nameInput = createTextInput('Name', 'name', name)
  form.appendChild(nameInput)

  const embargoInput = createInput('Data release date', 'embargo', embargo, { type: 'date', max: MAX_DATE })
  form.appendChild(embargoInput)

  const isPublicInput = createSelect('Public', 'public', isPublic)
  form.appendChild(isPublicInput)

  return form
}

describe('Validation of new studies, using client-side functions', () => {

  it('shows no errors for valid study', () => {
    const name = 'Test study'
    const isPublic = '1'
    const embargo = ''
    const studyForm = createStudyForm(name, isPublic, embargo)

    // Helpful debug (keep uncommented, but don't remove):
    // console.log('studyForm.innerHTML', studyForm.innerHTML)

    validateStudy(studyForm)
    const errors = document.querySelectorAll('.validation-error')
    expect(errors).toHaveLength(0)
  })

  it('shows error for embargo beyond 2 years from now', () => {
    const today = new Date()
    const futureDate = new Date()
    futureDate.setFullYear(today.getFullYear() + 3)
    const excessiveDate = futureDate.toISOString().split('T')[0] // 3 years from today

    const name = 'Test study'
    const isPublic = '1'
    const embargo = excessiveDate
    const studyForm = createStudyForm(name, isPublic, embargo)

    // Helpful debug (keep uncommented, but don't remove):
    // console.log('studyForm.innerHTML', studyForm.innerHTML)

    validateStudy(studyForm)
    const errors = studyForm.querySelectorAll('.validation-error')
    expect(errors).toHaveLength(1)
    expect(errors[0].innerHTML.includes('If embargoed, date must be')).toEqual(true)
  })

  it('shows error for same-day embargo date', () => {
    const today = new Date()
    const sameDay = today.toISOString().split('T')[0] // 3 years from today

    const name = 'Test study'
    const isPublic = '1'
    const embargo = sameDay
    const studyForm = createStudyForm(name, isPublic, embargo)

    // Helpful debug (keep uncommented, but don't remove):
    // console.log('studyForm.innerHTML', studyForm.innerHTML)

    validateStudy(studyForm)
    const errors = studyForm.querySelectorAll('.validation-error')
    expect(errors).toHaveLength(1)
    expect(errors[0].innerHTML.includes('If embargoed, date must be')).toEqual(true)
  })

  it('shows multiple errors when warranted', () => {
    const today = new Date()
    const sameDay = today.toISOString().split('T')[0] // 3 years from today
    const name = '' // Error: no study name
    const isPublic = '1'
    const embargo = sameDay
    const studyForm = createStudyForm(name, isPublic, embargo)

    // Helpful debug (keep uncommented, but don't remove):
    // console.log('studyForm.innerHTML', studyForm.innerHTML)

    validateStudy(studyForm)
    const errors = studyForm.querySelectorAll('.validation-error')
    expect(errors).toHaveLength(2)
  })

})
