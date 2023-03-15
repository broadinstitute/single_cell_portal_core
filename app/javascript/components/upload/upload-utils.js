import _get from 'lodash/get'
import React from 'react'

export const PARSEABLE_TYPES = ['Cluster', 'Coordinate Labels', 'Expression Matrix', 'MM Coordinate Matrix',
  '10X Genes File', '10X Barcodes File', 'Gene List', 'Metadata', 'Analysis Output', 'AnnData']

const EXPRESSION_INFO_TYPES = ['Expression Matrix', 'MM Coordinate Matrix']

// context to pass through UploadWizard
export const StudyContext = React.createContext(null)

/** properties used to track file state on the form, but that should not be sent to the server
 *  this also includes properties that are only modifiable on the server (and so should also
 * be ignored server side, but for best hygiene are also just not sent ) */
const PROPERTIES_NOT_TO_SEND = [
  'selectedFile',
  'uploadSelection',
  'submitData',
  'saveProgress',
  'isDirty',
  'isSaving',
  'isDeleting',
  'isError',
  'generation',
  'created_at',
  'updated_at',
  'queued_for_deletion',
  'upload_file_size',
  'data_dir',
  'options',
  'version',
  'status',
  'upload',
  'parse_status',
  'requestCanceller',
  'serverFile'
]

const PROPERTIES_AS_JSON = ['custom_color_updates']

/** gets an object representing a new, empty study file.  Does not communicate to server */
export function newStudyFileObj(studyId) {
  return {
    name: '',
    _id: generateMongoId(),
    status: 'new',
    description: '',
    parse_status: 'unparsed',
    spatial_cluster_associations: [],
    expression_file_info: {},
    heatmap_file_info: {}
  }
}

/** reworks the file object to make it easier to work with
  * maps the id property to _id, and sets undefined properties
  * this modifies the object in-place, but also returns it for easy chaining
  */
export function formatFileFromServer(file) {
  file._id = file._id.$oid
  file.description = file.description ? file.description : ''
  delete file.study_id
  if (file.taxon_id) {
    // Note that taxon_id here is a MongoDB object ID, not an NCBI Taxonomy ID like "9606".
    file.taxon_id = file.taxon_id.$oid
  }
  if (file.genome_assembly_id) {
    file.genome_assembly_id = file.genome_assembly_id.$oid
  }
  if (file.study_file_bundle_id) {
    file.study_file_bundle_id = file.study_file_bundle_id.$oid
  }
  if (file.expression_file_info) {
    delete file.expression_file_info._id
  }
  if (EXPRESSION_INFO_TYPES.includes(file.file_type) && !file.expression_file_info) {
    // some legacy studies will not have supplemental expression file info
    file.expression_file_info = {
      is_raw_counts: false,
      raw_counts_associations: []
    }
  }
  if (file.file_type === 'Gene List' && !file.heatmap_file_info) {
    // some legacy studies will not have supplemental heatmap file info
    file.heatmap_file_info = {
      custom_coloring: false,
      color_min: -1,
      color_max: 1
    }
  }
  return file
}

/** find the bundle children of 'file', if any, in the given 'files' list */
export function findBundleChildren(file, files) {
  return files.filter(f => {
    // check if the file is either explicity listed as a parent in the child's 'options' field,
    // or if the child and the parent are in the same study_file_bundle
    const parentFields = [
      f.options?.matrix_id,
      f.options?.bam_id,
      f.options?.cluster_file_id,
      f.study_file_bundle_id
    ]
    return parentFields.includes(file._id) ||
      file.study_file_bundle_id && parentFields.includes(file.study_file_bundle_id)
  })
}

/** return a new FormData based on the given file object, formatted as the api endpoint expects,
    cleaning out any excess params */
export function formatFileForApi(file, chunkStart, chunkEnd) {
  const data = new FormData()
  Object.keys(file).filter(key => !PROPERTIES_NOT_TO_SEND.includes(key)).forEach(key => {
    addObjectPropertyToForm(file, key, data)
  })
  if (file.uploadSelection) {
    if (chunkStart || chunkEnd) {
      data.append('study_file[upload]', file.uploadSelection.slice(chunkStart, chunkEnd), file.name)
    } else {
      data.append('study_file[upload]', file.uploadSelection)
    }
    data.append('study_file[parse_on_upload]', true)
  }
  if (file.options) {
    Object.keys(file.options).forEach(key => {
      data.append(`study_file[options][${key}]`, file.options[key])
    })
  }
  return data
}

/** Does basic validation of the file, including file existence, name, file type, and required fields
 * returns a hash of message keys to validation messages
 * allowedFileExts is an array of string extensions, e.g. ['.txt', '.csv']
 * requiredFields is array objects with label and propertyName:  e.g. [{label: 'species', propertyName: 'taxon_id'}]
 * it validates the propertyName is specified (propertyName can include '.' for nested properties), and
 * uses the label in the validation message returned if the property is not specified. */
export function validateFile({ file, allFiles, allowedFileExts=[], requiredFields=[], isAnnDataExperience=false }) {
  if (!file) {
    // edge case where the form is rendered but hook to add an empty file has not yet finished
    return { file: 'File not yet initialized' }
  }

  const validationMessages = {}
  if (file.status === 'new') {
    if (!file.uploadSelection) {
      validationMessages.uploadSelection = 'You must select a file to upload'
    }
  }

  if (file.uploadSelection) {
    if (!allowedFileExts.some(ext => file.uploadSelection.name.endsWith(ext))) {
      validationMessages.fileName = `Allowed extensions are ${allowedFileExts.join(' ')}`
    }
  }

  validateNameUniqueness(file, allFiles, validationMessages)
  validateBundleParent(file, allFiles, validationMessages)
  validateRequiredFields(file, requiredFields, validationMessages)

  return validationMessages
}

/** checks required fields are present */
function validateRequiredFields(file, requiredFields, validationMessages) {
  requiredFields.forEach(field => {
    const existingValue = _get(file, field.propertyName)
    const isBlank = !existingValue || (typeof existingValue === 'object' && existingValue.length === 0)
    if (isBlank) {
      validationMessages[field.propertyName] = `You must specify ${field.label}`
    }
  })
}

/** checks that a bundle parent is already saved */
function validateBundleParent(file, allFiles, validationMessages) {
  const parentId = file.options?.matrix_id || file.options?.bam_id || file.options?.cluster_file_id
  if (parentId) {
    // don't allow saving until parent file is saved
    const parentFile = allFiles.find(f => f._id === parentId)
    const parentSaved = parentFile && (parentFile.status !== 'new' || parentFile.isSaving)
    if (!parentSaved) {
      validationMessages['parentSaved'] = 'Parent file must be saved first'
    }
  }
}

/** checks that the file name is unique.
 * Just intended to catch clusters with duplicate names
 * Checking the selected upload file name's uniqueness is done in FileUploadControl */
function validateNameUniqueness(file, allFiles, validationMessages) {
  const allOtherFiles = allFiles.filter(f => f._id != file._id)
  const allOtherNames = allOtherFiles.map(f => f.name)
  // require 'isDirty' so we only show the error on the file being updated
  if (file.name && allOtherNames.includes(file.name) && file.isDirty) {
    validationMessages.fileName = `A file named ${file.name} already exists in your study`
  }
}

/** Because we are sending as FormData, rather than JSON, we need to split
    arrays and nested objects across multiple entries to deliver what Rails expects.
    The function below is informed by concepts from
    https://stackoverflow.com/questions/22783108/convert-js-object-to-form-data
    */
export function addObjectPropertyToForm(obj, propertyName, formData, nested) {
  let propString = `study_file[${propertyName}]`
  
  if (nested) {
    propString = `study_file[${nested}_attributes][${propertyName}]`
  }
  if (Array.isArray(obj[propertyName])) {
    if (obj[propertyName].length == 0) {
      // if the array is empty, send an empty string as an indication that it is cleared
      formData.append(`${propString}[]`, '')
    } else {
      // add each array entry as a separate form data entry
      obj[propertyName].forEach(val => {
        formData.append(`${propString}[]`, val)
      })
    }
  } else if (obj[propertyName] && typeof obj[propertyName] === 'object') {
    if (PROPERTIES_AS_JSON.includes(propertyName)) {
      // serialize the object as json
      formData.append(propString, JSON.stringify(obj[propertyName]))
    } else {
      // iterate over the keys and add each as a nested form property
      Object.keys(obj[propertyName]).forEach(subKey => {
        addObjectPropertyToForm(obj[propertyName], subKey, formData, propertyName)
      })
    }
  } else {
    // don't set null properties -- those are ones that haven't changed
    // and having them be sent as 'null' or '' can throw off validations
    if (obj[propertyName] != null && typeof obj[propertyName] != 'undefined') {
      formData.append(propString, obj[propertyName])
    }
  }
}

/** generates an id string suitable as a mongo id (24-character hex), see
 * https://stackoverflow.com/questions/10593337/is-there-any-way-to-create-mongodb-like-id-strings-without-mongodb
*/
export function generateMongoId() {
  const sFunc = n => Math.floor(n).toString(16)
  return sFunc(Date.now() / 1000) + ' '.repeat(16).replace(/./g, () => sFunc(Math.random() * 16))
}

const plainTextExtensions = ['.txt', '.tsv', '.text', '.csv']
const mtxExtensions = ['.mtx', '.mm', '.txt', '.text']
const imageExtensions = ['.jpeg', '.jpg', '.png', '.bmp']
const miscExtensions = ['.txt', '.text', '.tsv', '.csv', '.jpg', '.jpeg', '.png', '.pdf',
  '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.zip', '.loom', '.ipynb']
const sequenceExtensions = ['.fq', '.fastq', '.fq.tar.gz', '.fastq.tar.gz', '.fq.gz', '.fastq.gz', '.bam']
const baiExtensions = ['.bai']
const annDataExtensions = ['.h5', '.h5ad', '.hdf5']
const seuratExtensions = ['.Rds', '.rds', '.RDS', '.seuratdata', '.h5seurat', '.seuratdisk', '.Rda', '.rda']

export const FileTypeExtensions = {
  plainText: plainTextExtensions.concat(plainTextExtensions.map(ext => `${ext}.gz`)),
  mtx: mtxExtensions.concat(mtxExtensions.map(ext => `${ext}.gz`)),
  image: imageExtensions,
  misc: miscExtensions.concat(miscExtensions.map(ext => `${ext}.gz`)),
  sequence: sequenceExtensions,
  bai: baiExtensions,
  annData: annDataExtensions,
  seurat: seuratExtensions
}
