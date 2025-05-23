import stringSimilarity from 'string-similarity'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

// max number of autocomplete suggestions
export const NUM_SUGGESTIONS = 25

/** Get pathway name given pathway ID */
export function getPathwayName(pathwayId) {
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
  if (window.pathwayIdsByName) {
    return window.pathwayIdsByName
  }

  if (
    !window.Ideogram || !window.Ideogram.interactionCache ||
    Object.keys(window.Ideogram.interactionCache).length === 0
  ) {
    return {}
  }

  const pathwayCache = window.Ideogram.interactionCache

  // Lower-quality or buggy pathways
  const omittedPathways = [
    'WP1984', 'WP615', 'WP5096',
    'WP5520', 'WP5522', 'WP5523'
  ]

  const pathwayIdsByName = {}
  const pathwayEntries = Object.entries(pathwayCache)

  const idsAndCountsByGene = {}

  pathwayEntries.forEach(([gene, ixnObj]) => {
    ixnObj.result?.forEach(r => {

      if (omittedPathways.includes(r.id)) {
        return
      }

      pathwayIdsByName[r.name] = r.id
      if (idsAndCountsByGene[gene] && idsAndCountsByGene[gene][r.id]) {
        // If a pathway interaction for this gene has already been found,
        // then increment the count of interactions in this pathway
        idsAndCountsByGene[gene][r.id] += 1
      } else if (gene in idsAndCountsByGene === false) {
        idsAndCountsByGene[gene] = {}
        idsAndCountsByGene[gene][r.id] = 1
      } else {
        idsAndCountsByGene[gene][r.id] = 1
      }
    })
  })

  const rankedPathwaysByGene = {}
  Object.entries(idsAndCountsByGene).forEach(([gene, idsAndCounts]) => {
    // Result is an array of pathways, sorted by number of interactions in gene
    const rankedPathways = Object.entries(idsAndCounts).sort((a, b) => b[1] - a[1])
    rankedPathwaysByGene[gene.toUpperCase()] = rankedPathways.map(([pw, count]) => pw)
  })

  window.pathwayIdsByName = pathwayIdsByName
  window.rankedPathwaysByGene = rankedPathwaysByGene

  return pathwayIdsByName
}

/** Determine if input text is a pathway name */
export function getIsPathway(inputText) {
  if (!window.Ideogram || !window.Ideogram.interactionCache || !inputText) {
    return false
  }

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

/** Determine if text is included in part of pathway name */
export function getIsInPathwayTitle(inputText) {
  const isPathway = getIsPathway(inputText)
  if (isPathway) {
    return true
  }

  const pathwayIdsByName = getPathwayIdsByName()
  const pathwayNames = Object.keys(pathwayIdsByName)
  const inputTextLowerCase = inputText.toLowerCase()
  const isInPathwayName = pathwayNames.some(
    name => name.toLowerCase().includes(inputTextLowerCase)
  )

  return isInPathwayName
}

/** Get IDs of pathways that contain the gene from input text */
export function getPathwaysContainingGene(inputText) {
  const rankedPathwaysByGene = window.rankedPathwaysByGene

  if (!rankedPathwaysByGene || inputText.toUpperCase() in rankedPathwaysByGene === false) {
    return []
  }

  const pathwayIds = rankedPathwaysByGene[inputText.toUpperCase()]

  return pathwayIds
}

/** Get pathway names that include the input text */
function getPathwaySuggestions(inputText, maxPathwaySuggestions) {
  const flags = getFeatureFlagsWithDefaults()
  if (
    !window.Ideogram || !window.Ideogram.interactionCache ||
    !flags?.show_pathway_expression
  ) {
    return []
  }

  const pathwayIdsByName = getPathwayIdsByName()

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

  // If we can fit more suggestions, add any matches from genes in pathway
  const numSuggestionsLeft = maxPathwaySuggestions - pathwaySuggestions.length
  if (numSuggestionsLeft > 0) {
    const pathwayIds = getPathwaysContainingGene(inputText, window.rankedPathwaysByGene)
    pathwayIds.slice(0, numSuggestionsLeft).forEach(pathwayId => {
      const pathwayName = getPathwayName(pathwayId)
      const pathwayOption = { label: pathwayName, value: pathwayId, isGene: false }
      pathwaySuggestions.push(pathwayOption)
    })
  }

  return pathwaySuggestions
}

/**
 * Get list of autocomplete suggestions, based on input text
 *
 * Returns top matches: exact prefix matches, then similar matches
 *
 * @param {String} inputString String typed by user into text input
 * @param {Array<String>} targets List of strings to match against
 * @param {Boolean} includePathways Whether include pathway suggestions
 */
export function getAutocompleteSuggestions(inputText, targets, includePathways) {
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
  if (prefixMatches.length < NUM_SUGGESTIONS) {
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

  const maxPathwaySuggestions = NUM_SUGGESTIONS - prefixMatches.length
  let pathwaySuggestions = []
  if (includePathways) {
    pathwaySuggestions = getPathwaySuggestions(inputText, maxPathwaySuggestions)
  }

  const topGeneMatches = topMatches.slice(0, NUM_SUGGESTIONS)

  topMatches = topGeneMatches.concat(pathwaySuggestions)

  return topMatches
}
