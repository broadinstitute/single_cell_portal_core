
/** return a string key unique to the study and cluster */
function getKey(accession, cluster) {
  return `${accession}-${cluster}`
}

/** return a cache object
 *  it supports adding and retrieving past calls to cluster API endpoints
    via addScatterDataToCache() and getScatterData()
  */
export function newCache() {
  const cache = {
    entries: {}
  }

  cache.addScatterData = (accession, cluster, scatterData) => {
    const key = getKey(accession, cluster)
    cache.entries[key] = scatterData
  }

  cache.getScatterData = (accession, clusterName) => {
    const key = getKey(accession, clusterName)
    return cache.entries[key]
  }

  cache.hasScatterData = (accession, clusterName) => {
    const key = getKey(accession, clusterName)
    return key in cache.entries
  }
  return cache
}
