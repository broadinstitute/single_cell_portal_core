import { defineConfig } from 'vite'
import rubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'
import { readFileSync } from 'fs'
import { sentryVitePlugin } from '@sentry/vite-plugin'

// Match latest non-draft at https://github.com/broadinstitute/single_cell_portal_core/releases
const version = readFileSync('version.txt', { encoding: 'utf8' })
console.log('process.env.SENTRY_ORG:',process.env.SENTRY_ORG)

export default defineConfig({
  'define': {
    '__SCP_VERSION__': process.env.SCP_VERSION ? process.env.SCP_VERSION : version,
    '__FRONTEND_SERVICE_WORKER_CACHE__': process.env.VITE_FRONTEND_SERVICE_WORKER_CACHE,
    '__DEV_MODE__': process.env.VITE_DEV_MODE
  },
  'plugins': [
    // inject plugin needs to be first
    rubyPlugin(),
    react({
      jsxRuntime: 'classic'
    }),

    // Put the Sentry vite plugin after all other plugins
    sentryVitePlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,

      // Auth tokens can be obtained from https://sentry.io/settings/account/api/auth-tokens/
      // and need `project:releases` and `org:read` scopes
      authToken: process.env.SENTRY_AUTH_TOKEN
    })
  ],
  'build': {
    'sourcemap': true,
    'chunkSizeWarningLimit': 4096,
    'rollupOptions': {
      'output': {
        // Safely split out especially large third-party libraries
        // Fuller explanation: https://github.com/broadinstitute/single_cell_portal_core/pull/1668
        'manualChunks': {
          'morpheus-app': ['morpheus-app'],
          'plotly.js-dist': ['plotly.js-dist'],
          'igv': ['@single-cell-portal/igv']
        }
      }
    }
  },
  'server': {
    'hmr': {
      'host': '127.0.0.1',
      'protocol': 'ws',
      'timeout': 1.0
    }
  }
})
