/** Parse SCP HDF5 data in JavaScript */

import * as hdf5 from 'jsfive'
import { readFile } from 'node:fs/promises'

/** Parse HDF5 file object */
export function parse(hdf5ArrayBuffer, filename) {
  const hdf5File = new hdf5.File(hdf5ArrayBuffer, filename)
  const group = hdf5File.get('entry')
  const dataset = hdf5File.get('entry/collection_time')
  const value = dataset.value
  const attrs = dataset.attrs

  console.log('"entry" group:')
  console.log(group)
  console.log('')
  console.log('"entry/collection_time" dataset:')
  console.log(dataset)
  console.log('')
  console.log('"entry/collection_time" dataset value:')
  console.log(value)
  console.log('')
  console.log('"entry/collection_time" dataset attributes:')
  console.log(attrs)
}

/** Run program */
async function main() {
  const filepath = 'sans59510.nxs.ngv'
  // const jsonPath = `${jsonFpStem + gene }.json`
  const byteArray = await readFile(filepath)
  const hdf5ArrayBuffer = byteArray.buffer

  // Might work for HDF5 sync CSFV via:
  // response = await fetch(fileUrl)
  // hdf5ArrayBuffer = response.arrayBuffer()

  console.log('byteArray')
  console.log(byteArray)
  parse(hdf5ArrayBuffer, filepath)
}

main()
