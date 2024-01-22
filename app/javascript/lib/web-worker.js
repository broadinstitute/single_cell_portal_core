/** Web worker that wraps a CPU-intensive function */
function setViolinCellIndexesWorker() {
  /**
   * Set an index to apply cell filtering for this gene in violin plots.
   *
   * This is done 1 time per gene. It is a CPU-intensive function, so it
   * is processed in a non-main thread.
   */
  function setViolinCellIndexes(results, allCellNames) {
    const violinCellIndexes = {}
    Object.keys(results.values).forEach(group => {
      violinCellIndexes[group] = []
      const cellNames = results.values[group].cells
      for (let i = 0; i < cellNames.length; i++) {
        const cellName = cellNames[i]
        const cellIndex = allCellNames.indexOf(cellName)
        violinCellIndexes[group].push(cellIndex)
      }
    })
    return violinCellIndexes
  }

  // Set up message handling for web worker
  self.onmessage = function(event) {
    const [gene, results, allCellNames] = event.data

    const violinCellIndexes = setViolinCellIndexes(results, allCellNames)

    self.postMessage(
      [gene, violinCellIndexes]
    )
  }
}

/** Compute violin cell indexes, and wait for that to finish */
export async function workSetViolinCellIndexes(gene, results, allCellNames) {
  window.SCP.workers.violin.postMessage([gene, results, allCellNames])

  await new Promise(resolve => {
    /** Poll for gene in violinCellIndexes */
    function pollForIndex() {
      setTimeout(() => {
        if (gene in window.SCP.violinCellIndexes === false) {
          return pollForIndex()
        } else {
          resolve()
        }
      }, 50)
    }
    pollForIndex()
  })
}

/** Initialize web worker for violin plot cell indexing */
export function initViolinWorker() {
  window.SCP.violinCellIndexes = {}

  // Build a worker from an anonymous function body, and enable worker to be
  // initialized without a network request.
  //
  // Web workers like this enable CPU-intensive tasks to be done off the main
  // (i.e., UI) thread, which keeps the UX responsive while non-trivial work is
  // done in the browser.
  const blobURL = URL.createObjectURL(new Blob(['(',
    setViolinCellIndexesWorker.toString(),
    ')()'], { type: 'application/javascript' }))

  window.SCP.workers = {}
  window.SCP.workers.violin = new Worker(blobURL)

  window.SCP.workers.violin.onmessage = function(event) {
    const [gene, violinCellIndexes] = event.data
    window.SCP.violinCellIndexes[gene] = violinCellIndexes
  }

  // We don't need this after creating the worker
  URL.revokeObjectURL(blobURL)
}
