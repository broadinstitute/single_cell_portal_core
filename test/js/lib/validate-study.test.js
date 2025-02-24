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
  // console.log('in createStudyFormElement, attrs', attrs)
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
  const select = createStudyFormElement('select', displayLabel, id, value, attrs)
  return select
}

/** Create new study form DOM elements */
function createStudyForm(
  name, project, workspace, useExistingWorkspace, isPublic, embargo
) {
  const form = document.createElement('form')

  const nameInput = createTextInput('Name', 'name', name)
  form.appendChild(nameInput)

  const projectMenu = createSelect('Terra billing project', 'firecloud_project', project)
  form.appendChild(projectMenu)

  const embargoInput = createInput('Data release date', 'embargo', embargo, { type: 'date', max: MAX_DATE })
  form.appendChild(embargoInput)

  const isPublicInput = createSelect('Public', 'public', isPublic)
  form.appendChild(isPublicInput)

  const useExistingMenu = createSelect('Use existing workspace?', 'use_existing_workspace', useExistingWorkspace)
  form.appendChild(useExistingMenu)

  const workspaceInput = createTextInput('Existing Terra workspace', 'firecloud_workspace', workspace)
  form.appendChild(workspaceInput)

  return form
}

describe('Validation of new studies, using client-side functions', () => {

  it('shows no errors for valid study', () => {
    const name = 'Test study'
    const project = 'Default project'
    const workspace = ''
    const useExistingWorkspace = '0'
    const isPublic = '1'
    const embargo = ''
    const studyForm = createStudyForm(name, project, workspace, useExistingWorkspace, isPublic, embargo)

    // console.log('in it, studyForm', studyForm)
    console.log('in it, studyForm.innerHTML', studyForm.innerHTML)

    validateStudy(studyForm)
    const errors = document.querySelectorAll('.validation-error')
    console.log('errors', errors)
    expect(errors).toHaveLength(0)
  })


})
