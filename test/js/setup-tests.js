import { configure } from 'enzyme'
import Adapter from 'enzyme-adapter-react-16'
// Mock `window.location` with Jest spies and extend expect
import 'jest-location-mock'

configure({ adapter: new Adapter() })

// Jest breaks on `import.meta.hot`, so mock it
jest.mock('vite/import-meta-hot', () => {
  return jest.fn(() => false)
})

import { setGlobalMockFlag, setMockOrigin } from 'lib/scp-api'

setGlobalMockFlag(true)
setMockOrigin('https://localhost:3000')

// convert scrolls to no-ops as otherwise they will error
global.scrollTo = jest.fn()

// Needed for tests that import Plotly
window.URL.createObjectURL = function() {}
window.HTMLCanvasElement.prototype.getContext = () => {}

// Needed for violin plot tests per
// https://github.com/testing-library/dom-testing-library/releases/tag/v7.0.0
import MutationObserver from '@sheerun/mutationobserver-shim'
window.MutationObserver = MutationObserver

// Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
// This enables tests for SCP
global.ga = function(mock1, mock2, mock3, mock4) {
  return
}
