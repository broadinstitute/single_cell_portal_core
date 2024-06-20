/** Render update to reflect newly-selected features in IGV track */
export function updateTrack(trackIndex, filteredFeatures, igv, igvBrowser) {
  // How many layers of features can be stacked / piled up.
  // TODO (SCP-5662): eliminate this constraint
  const maxRows = 20

  igv.FeatureUtils.packFeatures(filteredFeatures, maxRows)

  const newFeatureCache = new igv.FeatureCache(filteredFeatures, igvBrowser.genome)
  igvBrowser.trackViews[trackIndex].track.featureSource.featureCache = newFeatureCache

  igvBrowser.trackViews[trackIndex].track.clearCachedFeatures()
  igvBrowser.trackViews[trackIndex].track.updateViews()
}
