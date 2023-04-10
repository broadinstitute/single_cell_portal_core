import { fetchCluster, fetchClusterUrl } from '~/lib/scp-api'
import { STEP_NOT_NEEDED } from '~/lib/metrics-perf'

/**
  @fileoverview Transparent caching mechanism for calls to fetchCluster
  For each call, it attempts to cache three separate things from the response:
    cellsAndCoords: the coordinates and cell names of the cluster
    annotations: an array of annotations
    expression: an array of expression values
  Prior to a new call, it checks the cache if any of those are available for the
  given params.  If so, it removes those fields from the list of fields to request from the server
  Once the response from the server comes back, it handles merging in all the cached fields into the
  response.

  For performance, this always copies by reference, e.g. it never clones an array of coordinates.
  This means, for example, that multiple plotly graphs will actually share underlying data structures.
  As far as I can tell, this is a good thing.  But this means extreme caution should be
  taken before modifying anything returned from a cache call, since it may be used
  in multiple places.

  Also for performance and debuggability, this stores at most one gene and one annotation
  and one set of expression values for a given cluster. These is no limit to the number
  of clusters this will cache, so it is up to the caller to call cache.clear().
  (note that because spatial data displays involve fetching multiple clusters on the
  same page view, it would be non-trivial for this cache to self-detect when a given
  cluster is fit to be removed from the cache)

  SIMPLE USAGE:

  const cache = newCache()

  cache.fetchCluster({params})

  cache.fetchCluster({same params})  // will not have to go the server

  cache.fetchCluster({same params, but different annotation}) // will only fetch the annotation values
   // does not refetch the cells/coords

*/


/**
  The Fields object is a collection of static helper methods, grouped by the field they help cache.

   For each separate field that we cache, we define a property on Fields, with
   get, put, and merge methods. Get and put are simple hash operations.
   Merge takes a server response object, and puts the relevant fields into the cache,
   or updates the response object with fields from the cache if they were not on the response object
   already
   */
const Fields = {
  cellsAndCoords: {
    getFromEntry: entry => entry.cellsAndCoords,
    putInEntry: (entry, cellsAndCoords) => entry.cellsAndCoords = cellsAndCoords,
    addFieldsOrPromise: (entry, fields, promises) => {
      const cachedCellsAndCoords = Fields.cellsAndCoords.getFromEntry(entry)
      if (cachedCellsAndCoords.then) {
        promises.push(cachedCellsAndCoords)
      } else if (!cachedCellsAndCoords.x) {
        fields.push('coordinates', 'cells')
      }
    },
    merge: (entry, scatter) => {
      const clusterFields = ['x', 'y', 'z', 'cells']
      clusterFields.forEach(field => {
        if (scatter.data[field]) {
          entry.cellsAndCoords[field] = scatter.data[field]
        }
        if (entry.cellsAndCoords[field]) {
          scatter.data[field] = entry.cellsAndCoords[field]
        }
      })
    }
  },

  annotation: {
    getFromEntry: (entry, annotationName, annotationScope) => {
      const key = getAnnotationKey(annotationName, annotationScope)
      return entry.annotations[key]
    },
    putInEntry: (entry, annotationName, annotationScope, annotations) => {
      const key = getAnnotationKey(annotationName, annotationScope)
      // we only cache one annotation at a time, so for now, delete any others
      entry.annotations = {}
      entry.annotations[key] = annotations
    },
    addFieldsOrPromise: (entry, fields, promises, annotationName, annotationScope) => {
      const cachedAnnotation = Fields.annotation.getFromEntry(entry, annotationName, annotationScope)
      if (!cachedAnnotation || annotationScope === 'user') {
        // because the requested name (the guid) for user annotations won't match the returned name
        // (the annotation's actual name), we don't cache user annotation values
        fields.push('annotation')
      } else if (cachedAnnotation.then && !promises.includes(cachedAnnotation)) {
        promises.push(cachedAnnotation)
      }
    },
    merge: (entry, scatter) => {
      if (scatter.data.annotations) {
        Fields.annotation.putInEntry(entry,
          scatter.annotParams.name,
          scatter.annotParams.scope,
          scatter.data.annotations)
      } else {
        scatter.data.annotations = Fields.annotation.getFromEntry(entry,
          scatter.annotParams.name,
          scatter.annotParams.scope)
      }
    }
  },

  expression: {
    getFromEntry: (entry, genes, consensus, expressionArray) => {
      if (expressionArray) {
        return expressionArray
      }
      const key = getExpressionKey(genes, consensus)
      return entry.expression[key]
    },
    putInEntry: (entry, genes, consensus, expression) => {
      const key = getExpressionKey(genes, consensus)
      // we only cache one set of expression data at a time, so for now, delete any others
      entry.expression = {}
      entry.expression[key] = expression
    },
    addFieldsOrPromise: (entry, fields, promises, genes, consensus, expressionArray) => {
      const cachedExpression = Fields.expression.getFromEntry(entry, genes, consensus, expressionArray)
      if (!cachedExpression) {
        fields.push('expression')
      } else if (cachedExpression.then && !promises.includes(cachedExpression)) {
        promises.push(cachedExpression)
      }
    },
    merge: (entry, scatter) => {
      if (scatter.data.expression) {
        Fields.expression.putInEntry(entry, scatter.genes, scatter.consensus, scatter.data.expression)
      } else {
        scatter.data.expression = Fields.expression.getFromEntry(entry, scatter.genes, scatter.consensus)
      }
    }
  },

  /** We have to also manage a fourth 'field' called clusterProps.  This stores
   all the other stuff on the response (axes, point size, etc...).  We mainly
   need this in the event we realize we can serve a response entirely with data from
   the cache.  This then allows us to reconstruct a full response */
  clusterProps: {
    getFromEntry: entry => entry.clusterProps,
    putInEntry: (entry, clusterProps) => entry.clusterProps = clusterProps,
    merge: (entry, scatter) => {
      // clusterProps caches everything except the data and allDataFromCache properties
      // eslint-disable-next-line no-unused-vars
      const { data, allDataFromCache, ...clusterProps } = scatter
      Object.assign(entry.clusterProps, clusterProps)
      Object.assign(scatter, entry.clusterProps)
      return clusterProps
    }
  }
}

/**
 * Get a fresh, empty cache.
 */
export function createCache() {
  const cache = {
    entries: {}
  }

  /** fetch cluster data, either from cache or the server, as appropriate
  * see fetchCluster in scp-api for parameter documentation
  * returns a promise */
  cache.fetchCluster = ({
    studyAccession, cluster, annotation, subsample, consensus,
    genes=[], isAnnotatedScatter=null, isCorrelatedScatter=null,
    expressionArray=null
  }) => {
    let apiCallPromise = null
    const { fields, promises } = cache._getFieldsToRequest({
      studyAccession, cluster, annotation, subsample, consensus, genes, isAnnotatedScatter,
      expressionArray
    })

    if (fields.length) {
      apiCallPromise = fetchCluster({
        studyAccession, cluster, annotation, subsample, consensus,
        genes, isAnnotatedScatter, isCorrelatedScatter, fields
      })
      const cacheEntry = cache._findOrCreateEntry(studyAccession, cluster, subsample)
      if (fields.includes('coordinates')) {
        Fields.cellsAndCoords.putInEntry(cacheEntry, apiCallPromise)
      }
      if (fields.includes('annotation')) {
        Fields.annotation.putInEntry(cacheEntry, annotation.name, annotation.scope, apiCallPromise)
      }
      if (fields.includes('expression')) {
        Fields.expression.putInEntry(cacheEntry, genes, consensus, apiCallPromise)
      }
    } else if (expressionArray) {
      apiCallPromise = Promise.resolve([
        {
          genes,
          consensus,
          cluster,
          subsample,
          annotParams: annotation,
          data: { expression: expressionArray },
          allDataFromCache: true // set a flag indicating that no fresh request to the server was needed
        }, {
          url: fetchClusterUrl({
            studyAccession, cluster, annotation,
            subsample, consensus, genes, isAnnotatedScatter
          }),
          legacyBackend: STEP_NOT_NEEDED,
          isClientCache: true,
          parse: STEP_NOT_NEEDED,
          requestStart: performance.now()
        }
      ])
    } else {
      apiCallPromise = Promise.resolve([
        {
          genes,
          consensus,
          cluster,
          subsample,
          annotParams: annotation,
          data: {},
          allDataFromCache: true // set a flag indicating that no fresh request to the server was needed
        }, {
          url: fetchClusterUrl({
            studyAccession, cluster, annotation,
            subsample, consensus, genes, isAnnotatedScatter
          }),
          legacyBackend: STEP_NOT_NEEDED,
          isClientCache: true,
          parse: STEP_NOT_NEEDED,
          requestStart: performance.now()
        }
      ])
    }
    promises.push(apiCallPromise)

    // Wait for completion of all promises for fetchCluster API calls, then merge them
    return Promise.all(promises).then(resultArray => {
      let mergedResult = null
      resultArray.forEach(result => {
        mergedResult = cache._mergeClusterResponse(studyAccession, result, cluster, annotation, subsample, genes)
      })
      return mergedResult
    }).catch(error => {
      // rather than try to reconstruct partial responses, clear the entire cache if an error occurs
      cache.clear()
      throw error
    })
  }

  /** Wipes the entire cache */
  cache.clear = () => {
    cache.entries = {}
  }


  /** adds the data for a given study/clusterName, overwriting any previous entry */
  cache._mergeClusterResponse = (accession, clusterResponse, requestedCluster, requestedAnnotation, requestedSubsample, requestedGenes) => {
    const scatter = clusterResponse[0]
    const cacheEntry = cache._findOrCreateEntry(accession, scatter.cluster, scatter.subsample)

    if (scatter.cluster !== requestedCluster || scatter.subsample !== requestedSubsample) {
      // if the returned cluster name is different (likely because we requested '_default' and then
      // got back the actual cluster name), also cache the response under the requested name
      cache._putEntry(accession, requestedCluster, requestedSubsample, cacheEntry)
    }
    if (scatter.allDataFromCache) {
      // we need the response cluster/subsample to mimic what actually came from the server for the graphs
      // to render correctly
      scatter.annotParams = cacheEntry.clusterProps.annotParams
      scatter.cluster = cacheEntry.clusterProps.cluster
      scatter.subsample = cacheEntry.clusterProps.subsample
    }
    Fields.clusterProps.merge(cacheEntry, scatter)
    Fields.cellsAndCoords.merge(cacheEntry, scatter)
    // only merge in annotation values if the annotation matches (or the default was requested, so
    // we can then assume the response matches)
    if (!requestedAnnotation.name || scatter.annotParams.name === requestedAnnotation.name) {
      Fields.annotation.merge(cacheEntry, scatter)
    }
    if (scatter.genes.length && scatter.genes.join('') === requestedGenes.join('')) {
      Fields.expression.merge(cacheEntry, scatter)
    }
    return clusterResponse
  }

  /** get the data for a given study/cluster.  Returns a blank entry if none exists */
  cache._findOrCreateEntry = (accession, clusterName, subsample) => {
    const key = getKey(accession, clusterName, subsample)

    if (!cache.entries[key]) {
      cache.entries[key] = {
        clusterProps: {},
        cellsAndCoords: {},
        annotations: {},
        expression: {}
      }
    }
    return cache.entries[key]
  }

  /** get the data for a given study/cluster */
  cache._putEntry = (accession, clusterName, subsample, entry) => {
    const key = getKey(accession, clusterName, subsample)
    cache.entries[key] = entry
  }

  /** based on cache contents and desired return values, returns an array suitable for the 'fields' argument
    * to fetchCluster in scp-api, and an array of promises for any in-flight requests relating to the needed data
     */
  cache._getFieldsToRequest = ({
    studyAccession, cluster, annotation, subsample, consensus, genes, isAnnotatedScatter, isCorrelatedScatter,
    expressionArray
  }) => {
    const fields = []
    const promises = [] // API call promises
    // we don't cache anything for annotated/correlated scatter since the coordinates are different per annotation/gene

    if (!isAnnotatedScatter && !isCorrelatedScatter) {
      if (subsample !== 'all') {
        // we also don't cache for subsampled views, since the cells and ordering may be different across annotations
        fields.push('coordinates', 'cells', 'annotation')
        if (genes.length) {
          fields.push('expression')
        }
      } else {
        const cacheEntry = cache._findOrCreateEntry(studyAccession, cluster, subsample)
        Fields.cellsAndCoords.addFieldsOrPromise(cacheEntry, fields, promises)
        Fields.annotation.addFieldsOrPromise(cacheEntry, fields, promises, annotation.name, annotation.scope)
        if (genes.length) {
          Fields.expression.addFieldsOrPromise(cacheEntry, fields, promises, genes, consensus, expressionArray)
        }
      }
    } else {
      fields.push('coordinates')
    }
    return { fields, promises }
  }

  return cache
}

/** returns a key for the cache entry of a given cluster */
function getKey(accession, cluster, subsample) {
  return `${accession}-${cluster}-${subsample}`
}

/** returns a key for the cache entry of a given annotation.  Name is guaranteed to be unique and we just
    add scope as an extra layer of safety/legibility */
function getAnnotationKey(annotationName, annotationScope) {
  return `${annotationName}-${annotationScope}`
}

/** returns a key for the cache entry of a given gene */
function getExpressionKey(gene, consensus) {
  return `${gene}-${consensus}`
}
