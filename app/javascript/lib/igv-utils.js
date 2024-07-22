/** Render update to reflect newly-selected features in IGV track */
export function updateTrack(trackIndex, filteredFeatures, igv, igvBrowser) {
  igv.FeatureUtils.packFeatures(filteredFeatures)

  const range = igvBrowser.trackViews[trackIndex].track.featureSource.featureCache.range
  const newFeatureCache = new igv.FeatureCache(filteredFeatures, igvBrowser.genome, range)
  igvBrowser.trackViews[trackIndex].track.featureSource.featureCache = newFeatureCache

  igvBrowser.trackViews[trackIndex].track.clearCachedFeatures()
  igvBrowser.trackViews[trackIndex].track.updateViews()
}
