module.exports = {
  verbose: true,
  transform: {
    '^.+\\.jsx?$': 'babel-jest'
  },
  transformIgnorePatterns: [
     // Bard client exports native ES6.
     // Jest can't import that without this line, but all modern browsers can.
     // This prevents SCP JavaScript tests from all throwing false positives.
     //
     // TODO (SCP-2705): Transpile Bard client to ease reuse
     // TODO (SCP-2688): Update Bard client docs to note dependents need this line
    'node_modules/(?!@databiosphere/bard-client)'
  ],
  setupFilesAfterEnv: ['./test/js/setup-tests.js'],
  testPathIgnorePatterns: [
    'config/webpack/test.js'
  ],
  moduleDirectories: [
    'app/javascript',
    'app/assets',
    'node_modules'
  ]
}
