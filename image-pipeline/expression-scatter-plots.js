/**
 * @fileoverview: Make static images of SCP gene expression scatter plots
 *
 * See adjacent README for installation, background
 *
 * To use, ensure you're on VPN, `cd image-pipeline`, then:
 *
 * node expression-scatter-plots.js --accession="SCP24" # Staging, 1.3M cell study
 */
import { mkdir, writeFile, readFile, access } from 'node:fs/promises'
import { createWriteStream } from 'node:fs'
import os from 'node:os'
import { exit } from 'node:process'
import { parseArgs } from 'node:util'

import { gunzipSync, strFromU8 } from 'fflate'
import puppeteer from 'puppeteer'
import sharp from 'sharp'
import { Storage } from '@google-cloud/storage'

let numLogEntries = 0

/** Print message with browser-tag preamble to local console and log file */
function print(message, context={}) {
  let preamble = ('preamble' in context === false) ? '' : context.preamble
  const timestamp = new Date().toISOString()
  if (preamble !== '') {preamble = `${preamble} `}
  const fullMessage = preamble + message

  console.log(fullMessage)

  logFileWriteStream.write(`[${timestamp}] -- : ${fullMessage }\n`)
  numLogEntries += 1

  // Stream logs to bucket in small chunks
  // For observability into ongoing jobs and crash-resilient logs
  if (numLogEntries % 20 === 0 && context.bucket) {uploadLog(context.bucket)}
}

/** Is request a log post to Bard? */
function isBardPost(request) {
  return request.url().includes('bard') && request.method() === 'POST'
}

/** Returns boolean for if request is relevant Bard / Mixpanel log */
function isExpressionScatterPlotLog(request) {
  if (isBardPost(request)) {
    const payload = JSON.parse(request.postData())
    const props = payload.properties
    return (payload.event === 'plot:scatter' && props.genes.length === 1)
  }
  return false
}

/** In Explore view, search gene, await plot, save plot image locally */
async function makeExpressionScatterPlotImage(gene, page, context) {
  // Trigger a gene search
  print(`Inputting search for gene: ${gene}`, context)
  await page.type('.gene-keyword-search input', gene, { delay: 1 })
  await page.keyboard.press('Enter')
  await page.$eval('.gene-keyword-search button', el => el.click())
  print(`Awaiting expression plot for gene: ${gene}`, context)

  // Wait for reliable signal that expression plot has finished rendering.
  // A Mixpanel / Bard log request always fires immediately upon render.
  await page.waitForRequest(request => {
    return isExpressionScatterPlotLog(request, gene)
  })

  page.waitForTimeout(250) // Wait for janky layout to settle

  // Prepare background colors for later transparency via `omitBackground`
  await page.evaluate(() => {
    document.querySelector('body').style.backgroundColor = '#FFF0'
    document.querySelector('.study-explore .plot').style.background = '#FFF0'
    document.querySelector('.explore-tab-content').style.background = '#FFF0'
    document.querySelector('.scatter-graph svg').style = null

    // Remove grid lines on X, Y, and (if present) Z axes
    document.querySelector('svg .cartesianlayer').remove()

    // Remove color filling vertical bar at right
    document.querySelector('svg defs .gradients').remove()

    // Remove axis labels, colorbar label (`magnitude` in Plotly.js)
    document.querySelector('svg .infolayer').remove()
  })

  // Height and width of plot, x- and y-offset from viewport origin
  const clipDimensions = { height: 595, width: 660, x: 5, y: 310 }

  const webpFileName = `${gene}.webp`
  // Take a screenshot, save it locally
  const rawImagePath = `${imagesDir}${gene}-raw.webp`
  const imagePath = `${imagesDir}${webpFileName}`
  await page.screenshot({
    path: rawImagePath,
    type: 'webp',
    clip: clipDimensions,
    omitBackground: true
  })

  // Hardcoded x, y placeholders below derived in processScatterPlots via:
  // console.log(Math.min(...plotlyTraces[0].x))
  // console.log(Math.max(...plotlyTraces[0].x))
  // console.log(Math.min(...plotlyTraces[0].y))
  // console.log(Math.max(...plotlyTraces[0].y))
  // These ought to be parseable via the `coordinates` array

  // Generalize if this moves beyond prototype
  const imageDescription = JSON.stringify({
    expression: [0, 2.433], // min, max of expression array
    x: [-12.568, 8.749], // min, max of x coordinates array
    y: [-15.174, 10.761], // min, max of y coordinates array
    z: []
  })

  // Embed Plotly.js settings directly into image file's Exif data
  await sharp(rawImagePath)
    .withMetadata({
      exif: {
        IFD0: {
          ImageDescription: imageDescription
        }
      }
    })
    .toFile(imagePath)

  print(`Wrote ${imagePath}`, context)

  // TODO (SCP-4698): parallelize upload, and atomically trigger on success.
  //
  // `gcloud storage cp` or (slower) `gsutil -m cp` would upload in parallel,
  // without needing to call GCS client library's bucket.upload on each file.
  // Ideally there would be a GCS client library equivalent of those commands,
  // but brief research found none.
  const stem = 'cache/expression_scatter/images/'
  const toFilePath = `${stem}${context.cluster}/${debugNonce}${webpFileName}`
  uploadToBucket(imagePath, toFilePath, context)

  return
}

/** Fetch JSON data for gene expression scatter plot, before loading page */
async function prefetchExpressionData(gene, context) {
  const { accession, preamble, origin, fetchOrigin, cluster } = context

  const extension = values['json-dir'] && initExpressionResponse ? '.gz' : ''
  const jsonPath = `${jsonFpStem}${gene}.json${extension}`

  print(`Prefetching JSON for ${gene}`, context)

  // Commented-out code is intended.  Use after incorporating `gcloud storage`.
  //
  // let isCopyOnFilesystem = true
  // try {
  //   await access(jsonPath)
  // } catch {
  //   isCopyOnFilesystem = false
  // }
  // if (isCopyOnFilesystem && initExpressionResponse) {
  //   // Don't process with fetch if expression was already prefetched
  //   print(`Using local expression data for ${gene} at ${jsonPath}`, context)
  //   return
  // }

  let jsonString
  if (!initExpressionResponse) {
    // Configure URLs
    const apiStem = `${fetchOrigin}/single_cell/api/v1`
    const allFields = 'coordinates%2Ccells%2Cannotation%2Cexpression'
    const params = `fields=${allFields}&gene=${gene}&subsample=all&isImagePipeline=true`
    const url = `${apiStem}/studies/${accession}/clusters/_default?${params}`

    // Fetch data
    const response = await fetch(url)
    const json = await response.json()

    if (Object.keys(coordinates).length === 0) {
      // Cache `coordinates` and `annotations` fields; this is done only once
      coordinates.x = json.data.x
      coordinates.y = json.data.y
      if ('z' in json.data) {
        coordinates.z = json.data.z
      }
      initExpressionResponse = json
    }
  }

  const fromFilePath = `_scp_internal/cache/expression_scatter/data/${cluster}/${gene}.json`
  const buffer = await downloadFromBucket(fromFilePath, context)
  const expressionArrayString = buffer.toString()

  if (values['json-dir']) {
    print('Populated initExpressionResponse for development run', context)
    return
  }

  expressionByGene[gene] = expressionArrayString

  // Uncomment code below for local debugging
  // await writeFile(jsonPath, jsonString)
  // print(`Wrote prefetched JSON: ${jsonPath}`, context)
}

/** Is this request on critical render path for expression scatter plots? */
function isAlwaysIgnorable(request) {
  const url = request.url()
  const isGA = url.includes('google-analytics')
  const isSentry = url.includes('ingest.sentry.io')
  const isNonExpPlotBardPost = isBardPost(request) && !isExpressionScatterPlotLog(request)
  const isIgnorableLog = isGA || isSentry || isNonExpPlotBardPost
  const isViolinPlot = url.includes('/expression/violin')
  const isIdeogram = url.includes('/ideogram@')
  return (isIgnorableLog || isViolinPlot || isIdeogram)
}

/** Return if request is for expression plot, and (if so) for which gene */
function detectExpressionScatterPlot(request) {
  const url = request.url()
  if (url.includes('expression&gene=')) {
    const gene = url.split('gene=')[1].split('&')[0]
    return [true, gene]
  } else {
    return [false, null]
  }
}

/** Drop extraneous requests, or replace requests that have pre-fetched data */
async function configureIntercepts(page) {
  await page.setRequestInterception(true)
  page.on('request', async request => {
    if (isAlwaysIgnorable(request)) {
      // Cancel requests not on critical render path, to minimize undue load
      request.abort()
    } else {
      const headers = Object.assign({}, request.headers())
      const [isESPlot, gene] = detectExpressionScatterPlot(request)
      if (isESPlot) {
        // TODO: Retain this block for now
        // Might be useful after incorporating `google storage cp`
        // const jsonPath = `${jsonFpStem + gene }.json`
        // const content = await readFile(jsonPath)

        const content = expressionByGene[gene]

        const expressionArrayString = content
        initExpressionResponse.data.expression = JSON.parse(expressionArrayString)
        const jsonString = JSON.stringify(initExpressionResponse)

        request.respond({
          status: 200,
          contentType: 'application/json',
          body: jsonString
        })
      } else {
        request.continue({ headers })
      }
    }
  })
}

/** CPU-level wrapper to make images for a sub-list of genes */
async function processScatterPlotImages(genes, context) {
  const { accession, preamble, origin } = context

  // Set up Puppeteer Chromium browser
  const pptrArgs = [
    '--ignore-certificate-errors',
    '--no-sandbox'
  ]
  // Map staging domain name to staging internal IP address on PAPI
  if (!process.env?.IS_LOCAL) {
    const dnsEntry = `${stagingHost.domainName} ${stagingHost.ip}`
    pptrArgs.push(`--host-rules=MAP ${dnsEntry}`)
  }
  const pptrArgsObj = { acceptInsecureCerts: true, args: pptrArgs }
  if (values.debug) {
    pptrArgsObj.headless = false
    pptrArgsObj.devtools = true
  }

  const browser = await puppeteer.launch(pptrArgsObj)

  const page = await browser.newPage()
  // Set user agent to Chrome "9000".
  // Bard client crudely parses UA, so custom raw user agents are infeasible.
  await page.setUserAgent(
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/9000.0.3904.108 Safari/537.36'
  )
  await page.setViewport({
    width: 1680,
    height: 1000,
    deviceScaleFactor: 1
  })

  const timeoutMilliseconds = timeoutMinutes * 60 * 1000
  // page.setDefaultTimeout(0) // No timeout
  page.setDefaultTimeout(timeoutMilliseconds)

  // Drop needless requests, re-route SCP API calls for expression data
  configureIntercepts(page)

  // Go to Explore tab in Study Overview page
  const params = `?subsample=all&isImagePipeline=true#study-visualize`
  const exploreViewUrl = `${origin}/single_cell/study/${accession}${params}`
  print(`Navigating to Explore tab: ${exploreViewUrl}`, context)
  await page.goto(exploreViewUrl)
  print(`Completed loading Explore tab`, context)

  print(`Number of genes to image: ${genes.length}`, context)

  await page.waitForSelector('#study-visualize-nav')
  await page.click('#study-visualize-nav')


  // // Helpful to debug if troubleshooting initial page display
  // const clipDimensions = { height: 1300, width: 1300, x: 0, y: 0 }
  // const webpFileName = `debug_${accession}_explore_view.webp`
  // const imagePath = `${imagesDir}${webpFileName}`
  // await page.screenshot({
  //   path: imagePath,
  //   type: 'webp',
  //   clip: clipDimensions,
  //   omitBackground: true
  // })
  // const toFilePath = `cache/expression_scatter/images/{debugNonce}${webpFileName}`
  // uploadToBucket(imagePath, toFilePath, preamble)

  await page.waitForSelector('.gene-keyword-search input')

  for (let i = 0; i < genes.length; i++) {
    const expressionPlotStartTime = Date.now()

    const gene = genes[i]
    await prefetchExpressionData(gene, context)
    await makeExpressionScatterPlotImage(gene, page, context)

    // Clear search input to avoid wrong plot type
    await page.$eval('.gene-keyword-search-input svg', el => el.parentElement.click())

    const expressionPlotPerfTime = Date.now() - expressionPlotStartTime
    print(`Expression plot time for gene ${gene}: ${expressionPlotPerfTime} ms`, context)
  }

  await browser.close()
}

/** Get a segment of the uniqueGenes array to process in given CPU */
function sliceGenes(uniqueGenes, numCPUs, cpuIndex) {
  const batchSize = Math.round(uniqueGenes.length / numCPUs)
  const start = batchSize * cpuIndex
  const end = batchSize * (cpuIndex + 1)
  return uniqueGenes.slice(start, end)
}

/** Make output directories if absent */
async function makeLocalOutputDir(leaf) {
  const dir = `output/${values.accession}/${leaf}/`
  const options = { recursive: true }
  try {
    await access(dir)
  } catch {
    await mkdir(dir, options)
  }
  return dir
}

/** Wrap argument parsing so it's more testable and loggable */
async function parseCliArgs() {
  const commandToNode = process.argv.join(' ').split('/').slice(-1)[0]

  const args = process.argv.slice(2)

  const options = {
    'accession': { type: 'string' }, // SCP accession
    'cluster': { type: 'string' }, // Name of clustering
    'bucket': { type: 'string' }, // Name of Google Cloud Storage (GCS) bucket
    'cores': { type: 'string' }, // Number of CPU cores to use. Default: all - 1
    'debug': { type: 'boolean' }, // Whether to show browser UI and exit early
    'debug-headless': { type: 'boolean' }, // Whether to exit early; for PAPI debugging
    'environment': { type: 'string' }, // development, staging, or production
    'json-dir': { type: 'string' } // Path to expression arrays; for development
  }
  const { values } = parseArgs({ args, options })

  const bucket = values.bucket
  print(`Command run via Node:\n\n${ commandToNode}\n`, { bucket })
  await uploadLog(bucket)

  // Candidates for CLI argument
  // CPU count on Intel i7 is 1/2 of reported, due to hyperthreading
  const numCPUs = values.cores ? parseInt(values.cores) : os.cpus().length / 2 - 1
  print(`Number of CPUs to be used on this client: ${numCPUs}`, { bucket })

  // Internal IP address for https://singlecell-staging.broadinstitute.org
  // Reference: singlecell-01 in
  // https://console.cloud.google.com/compute/instances?project=broad-singlecellportal-staging
  // This allows PAPI to access the staging web app server, which is
  // otherwise blocked per firewall / GCP Cloud Armor.
  const stagingIP = process.env?.STAGING_INTERNAL_IP
  const stagingDomainName = 'singlecell-staging.broadinstitute.org'
  const stagingHost = { ip: stagingIP, domainName: stagingDomainName }

  // TODO (SCP-4564): Document how to adjust network rules to use staging locally
  const originsByEnvironment = {
    'development': 'https://localhost:3000',
    'staging': `https://${ stagingDomainName}`,
    'production': 'https://singlecell.broadinstitute.org'
  }
  const environment = values.environment || 'development'
  const origin = originsByEnvironment[environment]

  // Set origin for use in standalone fetch, which lacks Puppeteer host map
  const isStagingPAPI = environment === 'staging' && !process.env?.IS_LOCAL
  const fetchOrigin = isStagingPAPI ? `https://${ stagingIP}` : origin

  return { values, numCPUs, origin, stagingHost, fetchOrigin }
}

/** Main function.  Run Image Pipeline */
async function run() {
  // Make directories for output images
  imagesDir = await makeLocalOutputDir('images')

  const rawCluster = values.cluster

  const cluster = rawCluster.replaceAll('+', 'pos').replace(/\W/g, '_')

  const bucket = values.bucket

  // Set and/or make directories for prefetched JSON
  let jsonDir
  if (values['json-dir']) {
    jsonDir = values['json-dir']
  } else {
    jsonDir = await makeLocalOutputDir('json')
  }
  jsonFpStem = `${jsonDir + cluster }--`

  // Cache for X, Y, and possibly Z coordinates
  coordinates = {}

  const accession = values.accession
  print(`Accession: ${accession}`, { bucket })

  await uploadLog(bucket)

  const crum = 'isImagePipeline=true'
  // Get list of all genes in study
  const exploreApiUrl = `${fetchOrigin}/single_cell/api/v1/studies/${accession}/explore?${crum}`
  print(`Fetching ${exploreApiUrl}`, { bucket })

  const response = await fetch(exploreApiUrl)

  // Helpful for debugging errors
  // const text = await response.text()
  // print('response text')
  // print(text)

  let json
  try {
    // json = JSON.parse(text) // Helpful to debug errors
    json = await response.json()
  } catch (error) {
    console.log('Failed to fetch:')
    console.log(exploreApiUrl)
    throw error
  }
  const uniqueGenes = json.uniqueGenes
  console.log(`Total number of genes: ${uniqueGenes.length}`)

  const processPromises = []
  for (let cpuIndex = 0; cpuIndex < numCPUs; cpuIndex++) {
    /** Log prefix to distinguish messages for different browser instances */
    const preamble = `Browser ${cpuIndex}:`

    // Pick a random gene
    // const geneIndex = Math.floor(Math.random() * uniqueGenes.length)
    // const gene = uniqueGenes[geneIndex]

    const context = {
      accession, preamble, origin, fetchOrigin, cluster, bucket
    }

    // Generate a series of plots, then save them locally
    let genes = sliceGenes(uniqueGenes, numCPUs, cpuIndex)
    if (values['debug'] || values['debug-headless']) {
      print('DEBUG: only processing 2 genes', context)
      genes = genes.slice(0, 2)
    }

    const processScatter = new Promise(resolve => {
      processScatterPlotImages(genes, context).then(() => {
        resolve()
      })
    })
    processPromises.push(processScatter)
  }
  await Promise.all(processPromises)
}

/** Fetch a file from a bucket to PAPI VM, return contents */
async function downloadFromBucket(fromFilePath, context) {
  const bucket = context.bucket // 'broad-singlecellportal-staging-testing-data'
  const content = await storage.bucket(bucket).file(fromFilePath).download()
  print(
    `File "${fromFilePath}" downloaded from bucket "${bucket}"`,
    context
  )
  return content
}

/** Upload a file from a local path to a destination path in a Google bucket */
async function uploadToBucket(fromFilePath, toFilePath, context) {
  const bucket = context.bucket // 'broad-singlecellportal-staging-testing-data'
  const opts = { destination: `_scp_internal/${toFilePath}` }
  await storage.bucket(bucket).upload(fromFilePath, opts)
  print(
    `File "${fromFilePath}" uploaded to destination "${toFilePath}" ` +
    `in bucket "${bucket}"`,
    context
  )
}

/** Upload / delocalize log file to GCS bucket */
async function uploadLog(bucket) {
  const context = { bucket }
  const logName = 'expression_scatter_images'
  await uploadToBucket('log.txt', `parse_logs/${logName}_${nonce}.txt`, context)
}

/**
 * Convert duration in milliseconds to hours, minutes, seconds (hh:mm:ss)
 * Source: https://stackoverflow.com/a/19700358
 */
function msToTime(duration) {
  const milliseconds = Math.floor((duration % 1000) / 100)
  let seconds = Math.floor((duration / 1000) % 60)
  let minutes = Math.floor((duration / (1000 * 60)) % 60)
  let hours = Math.floor((duration / (1000 * 60 * 60)) % 24)

  hours = (hours < 10) ? `0${ hours}` : hours
  minutes = (minutes < 10) ? `0${ minutes}` : minutes
  seconds = (seconds < 10) ? `0${ seconds}` : seconds

  return `${hours }:${ minutes }:${ seconds }.${ milliseconds}`
}

/** Wrap up job.  Log status, run time. */
async function complete(error=null) {
  const bucket = values.bucket
  const context = { bucket }
  if (error) {print(error.stack, context)}

  // Get timing data
  const endTime = Date.now()
  const perfTime = endTime - startTime // Duration in milliseconds
  const durationHMS = msToTime(perfTime) // Friendly time
  const durationNote = `Total run time: ${perfTime} ms (${durationHMS})`

  // Get status data
  const status = error ? 'failure' : 'success'
  const statusNote = `Status: ${status}`

  const signature = 'Completed Image Pipeline run'
  print(`\n${signature}.  ${statusNote}.  ${durationNote}\n\n`, context)

  await uploadLog(bucket)
}

const startTime = Date.now()
// Adds a unique signature to output; helpful when debugging

// Start time in ISO-8601 format, without colons
const timestamp = new Date().toISOString().split('.')[0].replace(/\:/g, '')
const nonceName = '' // e.g. "eweitz_"
const nonce = `_${nonceName}${timestamp}`

const storage = new Storage()

const timeoutMinutes = 2

const logFileWriteStream = createWriteStream('log.txt')

const { values, numCPUs, origin, stagingHost, fetchOrigin } = await parseCliArgs()

let debugNonce = ''
if (values['debug'] || values['debug-headless']) {
  debugNonce = `_debug${ nonce}/`
}

let imagesDir
let jsonFpStem
let coordinates
let initExpressionResponse
const expressionByGene = {}

try {
  await run()
  await complete()
} catch (error) {
  await complete(error)
  exit(1)
}


// // This executes immediately after calling main function.
// // Perhaps refactor that to use Promise.all, then call this as a function.
// console.log(`Timed out genes: ${Object.keys(timedOutGenes).length}`)
// console.log(timedOutGenes)

// const perfTime = Date.now() - startTime
// console.log(`Completed image pipeline, time: ${perfTime} ms`)
