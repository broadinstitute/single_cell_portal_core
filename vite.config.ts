import { defineConfig } from 'vite'
import rubyPlugin from 'vite-plugin-ruby'
import react from '@vitejs/plugin-react'
import { sentryVitePlugin } from '@sentry/vite-plugin'
import { readFileSync } from 'fs'

// Match latest non-draft at https://github.com/broadinstitute/single_cell_portal_core/releases
const version = readFileSync('version.txt', { encoding: 'utf8' })

// sentryVitePlugin should be disabled in local development as it prevents using breakpoints
// to turn off locally, run:
//
// DISABLE_SENTRY=true bin/vite dev
//
// otherwise, this evaluates to false and leaves plugin enabled in all other scenarios
const disableSentry = typeof process.env.DISABLE_SENTRY !== 'undefined' && process.env.DISABLE_SENTRY === 'true'

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
    sentryVitePlugin({
      'org': 'broad-institute',
      'project': 'single-cell-portal',
      'authToken': process.env.SENTRY_AUTH_TOKEN,
      'telemetry': false,
      'disable': disableSentry
    })
  ],
  'resolve': {
    'alias': {
      'lib/assets/metadata_schemas/alexandria_convention/alexandria_convention_schema.json': 'lib/assets/metadata_schemas/alexandria_convention/alexandria_convention_schema.json'
    }
  },
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
    },
    'allowedHosts' : ['vite'] // required for running inside docker-compose
  }
})
