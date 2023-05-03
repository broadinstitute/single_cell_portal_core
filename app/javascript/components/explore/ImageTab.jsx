import React, { useState, useEffect } from 'react'
import BucketImage from '~/components/visualization/BucketImage'
import ScatterPlot from '~/components/visualization/ScatterPlot'

/** Display reference images (e.g. tissue stains) beside spatial scatter plots */
export default function ImageTab({
  studyAccession,
  exploreParams,
  imageFiles,
  bucketName,
  isVisible,
  getPlotDimensions,
  isCellSelecting,
  plotPointsSelected,
  dataCache
}) {
  const [hasBeenVisible, setHasBeenVisible] = useState(isVisible)
  const hasAssociatedClusters = imageFiles.some(file => file.associated_clusters.length > 0)
  const [showClusters, setShowClusters] = useState(hasAssociatedClusters)

  useEffect(() => {
    if (isVisible) {
      setHasBeenVisible(true)
    }
  }, [isVisible])

  // don't start loading images/clusters until they click on the tab
  if (!hasBeenVisible) {
    return <div className="row">
      <div className="col-md-12 text-center">
        Loading...
      </div>
    </div>
  }
  let isMultiRow = false
  if (imageFiles.length > 1 || imageFiles[0].associated_clusters.length > 1) {
    isMultiRow = true
  }
  const imageColClass = showClusters ? 'col-md-6' : 'col-md-12 text-center'

  return <div>
    { hasAssociatedClusters &&
      <div className="row padded" style={{ borderBottom: '1px solid #ccc' }}>
        <div className="col-md-6 ">
          <h5 className="text-center">Images</h5>
        </div>
        <div className="col-md-6">
          <h5 className="text-center">
            Associated Clusters
            <button className="action" aria-label="Toggle show clusters" onClick={() => setShowClusters(!showClusters)}>
              [{showClusters ? 'hide' : 'show'}]
            </button>
          </h5>
        </div>
      </div>
    }
    { imageFiles.map(file => {
      return <div className="row" key={file.name}>
        <div className={imageColClass}>
          <h5 className="plot-title">{file.name}</h5>
          <BucketImage fileName={file.bucket_file_name} bucketName={bucketName}/>
          <p className="help-block">
            { file.description &&
              <span>{file.description}</span>
            }
          </p>
        </div>
        { showClusters &&
          <div className="col-md-6">
            { file.associated_clusters.map(clusterName => {
              const clusterParams = {
                ...exploreParams,
                cluster: clusterName
              }
              return <div key={clusterName}>
                <ScatterPlot
                  studyAccession={studyAccession}
                  {...clusterParams}
                  dimensions={getPlotDimensions({
                    isMultiRow,
                    isTwoColumn: true,
                    hasTitle: true,
                    showRelatedGenesIdeogram: false
                  })}
                  isCellSelecting={isCellSelecting}
                  plotPointsSelected={plotPointsSelected}
                  dataCache={dataCache}
                />
              </div>
            })}
          </div>
        }
      </div>
    })}
  </div>
}
