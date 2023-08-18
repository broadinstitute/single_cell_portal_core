/**
 * Get width and height of given text in pixels.
 *
 * Background: https://erikonarheim.com/posts/canvas-text-metrics/
 */
function getTextSize(text, font) {
  // re-use canvas object for better performance
  const canvas =
    getTextSize.canvas ||
    (getTextSize.canvas = document.createElement('canvas'))
  const context = canvas.getContext('2d')
  context.font = font
  const metrics = context.measureText(text)

  // metrics.width is less precise than technique below
  const right = metrics.actualBoundingBoxRight
  const left = metrics.actualBoundingBoxLeft
  const width = Math.abs(left) + Math.abs(right)

  const height =
    Math.abs(metrics.actualBoundingBoxAscent) +
    Math.abs(metrics.actualBoundingBoxDescent)

  return { width, height }
}

/** Get min-width of container for menus on help, create study, and sign in / username */
export function getGlobalHeaderEndWidth(text, font) {
  const baseWidth = 249 // Width of "Help", "Create study", icons, padding, etc.
  const userOrSignInTextWidth = getTextSize(text, font).width
  const globalHeaderEndWidth = baseWidth + userOrSignInTextWidth
  return globalHeaderEndWidth
}

/** Set min-width of container for menus on help, create study, and sign in / username */
export function setGlobalHeaderEndWidth() {
  const globalHeaderEnd = document.getElementById('scp-navbar-dropdown-collapse')
  const userOrSignInText = Array.from(globalHeaderEnd.children).slice(-1)[0].innerText
  const font = window.getComputedStyle(globalHeaderEnd, null).getPropertyValue('font')
  const minWidth = getGlobalHeaderEndWidth(userOrSignInText, font)
  globalHeaderEnd.style.minWidth = `${minWidth}px`
}
