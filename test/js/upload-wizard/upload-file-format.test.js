import '@testing-library/jest-dom'
import { formatFileForApi } from 'components/upload/upload-utils'
import { RAW_COUNTS_FILE, METADATA_FILE } from './file-info-responses'



const FORMAT_FOR_API_TEST_FILE = {
  '_id': {
    '$oid': '60a2b9fccc7ba082358b544f'
  },
  'description': '',
  'expression_file_info': {
    '_id': {
      '$oid': '6155ef87cc7ba01c87884e77'
    },
    'raw_counts_associations': ['fakeFileId'],
  },
  'file_type': 'Expression Matrix',
  'name': 'raw2_chicken_40_cells_4_genes.processed_dense.txt',
  'options': { 'key1': 'value1' },
  'study_id': {
    '$oid': '60a2b9f4cc7ba082358b5448'
  },
  'taxon_id': {
    '$oid': '604009b9cc7ba03e1b277a40'
  }
}


describe('a new FormData is created for valid file uploads', () => {
  const fileEnd = 10000
  const fileStart = 0

  it('processes a raw counts file correctly', async () => {
    const file = RAW_COUNTS_FILE
    const result = formatFileForApi(file, fileStart, fileEnd)

    expect(result.get('study_file[name]')).toEqual('example_raw_counts.txt')
    expect(result.get('study_file[file_type]')).toEqual('Expression Matrix')
  })
  it('processes a metadata file correctly', async () => {
    const file = METADATA_FILE
    const result = formatFileForApi(file, fileStart, fileEnd)

    expect(result.get('study_file[name]')).toEqual('metadata.txt')
    expect(result.get('study_file[file_type]')).toEqual('Metadata')
  })
  it('processes an expression file correctly', async () => {
    const file = FORMAT_FOR_API_TEST_FILE
    const result = formatFileForApi(file, fileStart, fileEnd)

    expect(result.get('study_file[name]')).toEqual('raw2_chicken_40_cells_4_genes.processed_dense.txt')
    expect(result.get('study_file[file_type]')).toEqual('Expression Matrix')
    expect(result.get('study_file[options][key1]')).toEqual('value1')
    expect(result.get('study_file[expression_file_info_attributes][raw_counts_associations][]')).toEqual('fakeFileId')

  })
})
