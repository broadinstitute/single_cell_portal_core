import React from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'

/** Convert gene names to pill-shaped badges */
function makeGeneBadges(genes) {
  return genes.map(gene => {
    return <span className="badge popover-badge" key={gene}>{gene}</span>
  })
}

/** Divide gene list into two parts, only showing first 3 */
export function formatGeneList(genes) {
  const shown = genes.slice(0, 3)
  const hidden = genes.slice(3, genes.length + 1)
  const formattedGenes = makeGeneBadges(shown)
  if (hidden.length === 0) {
    return formattedGenes
  }
  const hiddenGenes = <Popover id="genes-tooltip" className="tooltip-wide">{makeGeneBadges(hidden)}</Popover>
  const hiddenOverlay = <OverlayTrigger trigger={['hover', 'focus']} key='hidden-genes' rootClose placement="right"
    overlay={hiddenGenes}>
    <span className='badge'>and {hidden.length} more</span>
  </OverlayTrigger>
  formattedGenes.push(hiddenOverlay)
  return formattedGenes
}

/** Get text for scatter plot title and optional detail */
export function getTitleTexts(cluster, genes, consensus, subsample, isCorrelatedScatter) {
  let titleText = cluster
  let detailText = ''

  if (genes.length) {
    const geneList = formatGeneList(genes)
    if (isCorrelatedScatter) {
      geneList.splice(1, 0, <span key="vs"> vs. </span>)
    }

    detailText = cluster
    if (consensus) {
      geneList.push(<span key="c">{consensus}</span>)
    }
    geneList.push(<span key="e"> expression</span>)
    titleText = geneList
  }
  if (subsample && subsample !== 'all' && !isCorrelatedScatter) {
    detailText = `subsample[${subsample}]`
  }

  return [titleText, detailText]
}

/** Renders a plot title for scatter plots */
export default function PlotTitle({
  titleTexts, isCorrelatedScatter, correlation
}) {
  const tooltipText =
    `If this value looks different than what you expect given the plot,
    the data may not be suited for correlation analysis and you should trust the plot`

  const [titleText, detailText] = titleTexts

  return <h5 className="plot-title">
    <span className="cluster-title">{titleText} </span>
    <span className="detail"> {detailText} </span>
    { isCorrelatedScatter && !!correlation &&
    <>
      <span className="correlation icon-left">
        Spearman rho = { Math.round(correlation * 1000) / 1000}
      </span>
      <span
        data-analytics-name="bulk-correlation-tooltip"
        data-toggle="tooltip"
        data-original-title={tooltipText}
      >
        <FontAwesomeIcon className="action help-icon" icon={faInfoCircle} />
      </span>
    </>
    }
  </h5>
}
