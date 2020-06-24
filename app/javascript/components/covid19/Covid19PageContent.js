import React, { useContext } from 'react'
import { Router } from '@reach/router'

import HomePageContent from 'components/HomePageContent'

/**
 * Render home page search but with covid-19 content and labels
 */
export default function Covid19PageContent() {
  let presetEnv = {
    showCommonButtons: false,
    keywordPrompt: "Search within COVID-19 studies",
    geneKeywordPrompt: "Search for genes within COVID-19 studies",
    preset: "covid19"
  }
  return (
    <HomePageContent presetEnv={presetEnv}/>
  )
}
