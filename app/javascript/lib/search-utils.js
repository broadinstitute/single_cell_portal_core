import stringSimilarity from 'string-similarity'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

// max number of autocomplete suggestions
export const NUM_SUGGESTIONS = 50

/** Get object mapping pathway names to WikiPathways IDs */
function getPathwayIdsByName(pathwayCache) {
  if (window.pathwayIdsByName) {
    return window.pathwayIdsByName
  }

  const pathwayIdsByName = {}
  const genesByPathwayId = {}
  Object.entries(pathwayCache).forEach(([gene, ixnObj]) => {
    ixnObj.result.forEach(r => pathwayIdsByName[r.name] = r.id)
  })

  console.log('in getPathwayIdsByName, pathwayIdsByName', pathwayIdsByName)

  window.pathwayIdsByName = pathwayIdsByName
  return pathwayIdsByName
}

/** Determine if input text is a pathway name */
export function getIsPathwayName(inputText) {
  if (!window.ideogram || !window.ideogram.interactionCache) {
    return []
  }

  const pathwayIdsByName = getPathwayIdsByName(window.ideogram.interactionCache)
  const pathwayNames = Object.keys(pathwayIdsByName)
  const isPathwayName = pathwayNames.some(
    name => name.toLowerCase() === inputText.toLowerCase()
  )

  return isPathwayName
}

/** Get pathway names that include the input text */
function getPathwaySuggestions(inputText) {
  const flags = getFeatureFlagsWithDefaults()
  if (
    !window.ideogram || !window.ideogram.interactionCache ||
    !flags?.show_pathway_expression
  ) {
    return []
  }

  const pathwayIdsByName = getPathwayIdsByName(window.ideogram.interactionCache)
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
