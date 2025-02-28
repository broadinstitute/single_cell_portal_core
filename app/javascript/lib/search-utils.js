import stringSimilarity from 'string-similarity'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

// max number of autocomplete suggestions
export const NUM_SUGGESTIONS = 50

/** Get pathway name given pathway ID */
export function getPathwayName(pathwayId) {
  console.log('pathwayId', pathwayId)
  if (window.pathwayNamesById) {
    return window.pathwayNamesById[pathwayId]
  }

  const pathwayNamesById = {}

  const pathwayIdsByName = getPathwayIdsByName()
  Object.entries(pathwayIdsByName).forEach(([name, id]) => {
    pathwayNamesById[id] = name
  })

  window.pathwayNamesById = pathwayNamesById

  const pathwayName = pathwayNamesById[pathwayId]

  return pathwayName
}

/** Get object mapping pathway names to WikiPathways IDs */
function getPathwayIdsByName() {
  console.log('in getPathwayIdsByName')
  if (window.pathwayIdsByName) {
    return window.pathwayIdsByName
  }

  if (
    !window.Ideogram || !window.Ideogram.interactionCache ||
    Object.keys(window.Ideogram.interactionCache).length === 0
  ) {
    console.log('exiting getPathwayIdsByName early')
    return {}
  }

  const pathwayCache = window.Ideogram.interactionCache

  const pathwayIdsByName = {}
  const pathwayEntries = Object.entries(pathwayCache)
  pathwayEntries.forEach(([gene, ixnObj]) => {
    ixnObj.result?.forEach(r => pathwayIdsByName[r.name] = r.id)
  })

  console.log('in getPathwayIdsByName, pathwayIdsByName', pathwayIdsByName)
  window.pathwayIdsByName = pathwayIdsByName
  return pathwayIdsByName
}

/** Determine if input text is a pathway name */
export function getIsPathway(inputText) {

  console.log('in getIsPathway, !window.Ideogram', !window.Ideogram)
  console.log('in getIsPathway, !window.Ideogram.interactionCache', !window.Ideogram.interactionCache)
  console.log('in getIsPathway, !inputText', !inputText)
  if (!window.Ideogram || !window.Ideogram.interactionCache || !inputText) {
    console.log('exiting getIsPathway early')
    return false
  }

  // console.log('inputText', inputText)

  const pathwayIdsByName = getPathwayIdsByName()

  const pathwayIds = Object.values(pathwayIdsByName)
  const inputTextUpperCase = inputText.toUpperCase()
  const isPathwayId = pathwayIds.some(
    id => id === inputTextUpperCase
  )
  if (isPathwayId) {
    return true
  }

  const pathwayNames = Object.keys(pathwayIdsByName)
  const inputTextLowerCase = inputText.toLowerCase()
  const isPathwayName = pathwayNames.some(
    name => name.toLowerCase() === inputTextLowerCase
  )

  return isPathwayName
}

/** Get pathway names that include the input text */
function getPathwaySuggestions(inputText) {
  console.log('in getPathwaySuggestions, inputText', inputText)
  console.log('in getPathwaySuggestions, window.Ideogram', window.Ideogram)
  console.log('in getPathwaySuggestions, window.Ideogram.interactionCache', window.Ideogram.interactionCache)
  const flags = getFeatureFlagsWithDefaults()
  if (
    !window.Ideogram || !window.Ideogram.interactionCache ||
    !flags?.show_pathway_expression
  ) {
    console.log('exiting getPathwaySuggestions early')
    return []
  }

  const pathwayIdsByName = getPathwayIdsByName()

  console.log('getPathwaySuggestions, pathwayIdsByName', pathwayIdsByName)

  const pathwayNames = Object.keys(pathwayIdsByName)
  const rawSuggestions = pathwayNames.filter(
    name => name.toLowerCase().includes(inputText.toLowerCase())
  )
  const pathwaySuggestions = rawSuggestions.map(pathwayName => {
    const pathwayId = pathwayIdsByName[pathwayName]

    // As expected by autocomplete in study gene search
    const pathwayOption = { label: pathwayName, value: pathwayId, isGene: false }
    return pathwayOption
  })

  return pathwaySuggestions
}

/**
 * Get list of autocomplete suggestions, based on input text
 *
 * Returns top matches: exact prefix matches, then similar matches
 *
 * @param {String} inputString String typed by user into text input
 * @param {Array<String>} targets List of strings to match against
 * @param {Integer} numSuggestions Number of suggestions to show
 */
export function getAutocompleteSuggestions(inputText, targets, numSuggestions=NUM_SUGGESTIONS) {
  // Autocomplete when user starts typing
  if (!targets?.length || !inputText) {
    return []
  }

  const text = inputText.toLowerCase()

  const exactMatch = targets.find(gene => gene === inputText)

  // Get genes that start with the input text
  const prefixMatches =
    targets
      .filter(gene => {
        return gene !== inputText && gene.toLowerCase().startsWith(text)
      })
      .sort((a, b) => {return a.localeCompare(b)})

  let topMatches = prefixMatches
  if (prefixMatches.length < numSuggestions) {
    // Get similarly-named genes, as measured by Dice coefficient (`rating`)
    const similar = stringSimilarity.findBestMatch(inputText, targets)
    const similarMatches =
        similar.ratings
          .sort((a, b) => b.rating - a.rating) // Rank larger numbers higher
          .filter(match => {
            const target = match.target
            return target !== inputText && !prefixMatches.includes(target)
          })
          .map(match => match.target)
    // Show top matches -- exact match, prefix matches, then similar matches
    topMatches = topMatches.concat(similarMatches)
  }

  if (exactMatch) {topMatches.unshift(exactMatch)} // Put any exact match first

  const pathwaySuggestions = getPathwaySuggestions(inputText, targets)

  const topGeneMatches = topMatches.slice(0, numSuggestions)

  topMatches = topGeneMatches.concat(pathwaySuggestions)

  return topMatches


}
