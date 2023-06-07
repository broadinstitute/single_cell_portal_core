import stringSimilarity from 'string-similarity'

// max number of autocomplete suggestions
export const NUM_SUGGESTIONS = 50

/**
 * Get list of autocomplete suggestions, based on input text
 *
 * Returns top matches: exact prefix matches, then similar matches
 *
 * @param {String} inputString String typed by user into text input
 * @param {Array<String>} targets List of strings to match against
 * @param {Integer} numSuggestions Number of suggestions to show
 */
export function getAutocompleteSuggestions(inputText, targets, numSuggestions= NUM_SUGGESTIONS) {
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
  return topMatches.slice(0, numSuggestions)
}
