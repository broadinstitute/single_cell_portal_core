module.exports = {
  verbose: true,
  transform: {
    '^.+\\.(js|jsx)$': 'babel-jest'
  },
  transformIgnorePatterns: [
    // Bard client exports native ES6.
    // Jest can't import that without this line, but all modern browsers can.
    // This prevents SCP JavaScript tests from all throwing false positives.
    //
    // TODO (SCP-2705): Transpile Bard client to ease reuse
    // TODO (SCP-2688): Update Bard client docs to note dependents need this line
    'node_modules/(?!@databiosphere/bard-client)',
    '\\.png'
  ],
  setupFilesAfterEnv: ['./test/js/setup-tests.js'],
  testPathIgnorePatterns: [
    'config/webpack/test.js'
  ],
  moduleDirectories: [
    'app/javascript',
    'app/assets',
    'node_modules'
  ],
  moduleNameMapper: {
    '\\.(jpg|ico|jpeg|png|gif|eot|otf|webp|svg|ttf|woff|woff2|mp4|webm|wav|mp3|m4a|aac|oga)$': '<rootDir>/test/js/jest-mocks/file-mock.js',
    '^~/(.*)$': '$1', // strip off the ~/, as jest doesn't need it since it has configured module directories
    '@single-cell-portal/igv': '<rootDir>/test/js/jest-mocks/igv-mock.js', // mock igv as jest has trouble parsing it
    'ideogram': '<rootDir>/test/js/jest-mocks/file-mock.js', // mock igv as jest has trouble parsing it
    '\\.css$': '<rootDir>/test/js/jest-mocks/file-mock.js', // mock CSS files as jest has trouble parsing them
    '^@single-cell-portal/hdf5-indexed-reader$': '<rootDir>/node_modules/@single-cell-portal/hdf5-indexed-reader/dist/hdf5-indexed-reader.node.cjs',
    'lib/assets/metadata_schemas/alexandria_convention/alexandria_convention_schema.json': '<rootDir>/lib/assets/metadata_schemas/alexandria_convention/alexandria_convention_schema.json'
  }
}
