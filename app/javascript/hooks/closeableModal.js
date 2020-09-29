import { useEffect, useRef } from 'react'

/**
 * Hook for a component that shows/hides a modal on click.  the modal will also close on
 * any clicks outside the modal.
 * @param show -  boolean - whether the modal is currently visible
 * @param setShow - function - setter for show ( e.g. [show, setShow] = useState(false)  )
 * @return an object with
         node:  a ref to attach to the button/ui component that toggles the modal
         clearNode: a ref to attach to any buttons that auto-close the modal
         handleButtonClick: a handler function to attach to the modal toggler.

  Example usage might be:

  const [show, setShow] = useState(false)
  const { node, clearNode, handleButtonClick } = useCloseableModal(show, setShow)
  <span ref={node}>
    <a onClick={handleButtonClick}>Toggle thingy</a>
    <a ref={clearNode}>Close thingy</a>
    { show && <thingy/> }
  </span>
 */
export default function useCloseableModal(show, setShow) {
  const clearNode = useRef()
  /** Click on the facet control itself */
  function handleButtonClick(e) {
    if (clearNode.current && clearNode.current.contains(e.target)) {
      setShow(false)
    } else {
      setShow(!show)
    }
  }

  const node = useRef()
  const handleOtherClick = e => {
    if (node.current.contains(e.target)) {
      // click was inside the modal, do nothing
      return
    }
    setShow(false)
  }

  // add event listener to detect clicks outside the modal,
  // so we know to close it
  // see https://medium.com/@pitipatdop/little-neat-trick-to-capture-click-outside-with-react-hook-ba77c37c7e82
  useEffect(() => {
    // add when mounted
    document.addEventListener('mousedown', handleOtherClick)
    // return function to be called when unmounted
    return () => {
      document.removeEventListener('mousedown', handleOtherClick)
    }
  }, [])

  return { node, clearNode, handleButtonClick }
}
