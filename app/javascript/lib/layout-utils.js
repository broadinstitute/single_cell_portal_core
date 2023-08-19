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

/** Get rendered value for a CSS style property in a DOM element */
function getStyle(domElement, prop) {
  return window.getComputedStyle(domElement, null).getPropertyValue(prop)
}

/** Convert string pixel value from CSS to an integer, e.g. "14px" -> 14 */
function pxToNumber(pxStyleValue) {
  return parseFloat(pxStyleValue.slice(0, -2))
}

/**
 * Set global header end width, and mitigate long study titles on narrow screens
 */
export function adjustGlobalHeader() {
  if (window.SCP.analyticsPageName !== 'site-study') {return}

  // Set min-width of container for menus on help, create study, and sign in / username
  const globalHeaderEnd = document.getElementById('scp-navbar-dropdown-collapse')
  const userOrSignInText = Array.from(globalHeaderEnd.children).slice(-1)[0].innerText
  const font = getStyle(globalHeaderEnd, 'font')
  const minWidth = getGlobalHeaderEndWidth(userOrSignInText, font)
  globalHeaderEnd.style.minWidth = `${minWidth}px`

  // Mitigate truncation edge case for very long titles
  //
  // If study title is smaller than its container, and user's screen is basically maximized,
  // then slightly decrease font size of study title, and slightly enlarge container.
  const studyHeader = document.querySelector('.study-header')
  const studyHeaderWidth = studyHeader.clientWidth
  const titleText = studyHeader.innerText
  const titleFont = getStyle(studyHeader, 'font')
  const studyTitleWidth = getTextSize(titleText, titleFont).width
  const isMaxWidth = window.screen.availWidth - window.innerWidth < 50
  if (studyTitleWidth > studyHeaderWidth && isMaxWidth) {
    // Decrease font size by 1px and padding at left by 1/2 original
    const fontSize = pxToNumber(getStyle(studyHeader, 'font-size')) // e.g. '14px' -> 14
    const smallerFontSize = `${fontSize - 1}px`
    studyHeader.style.fontSize = smallerFontSize
    const paddingLeft = pxToNumber(getStyle(studyHeader, 'padding-left'))
    const smallerPaddingLeft = `${paddingLeft / 2}px`
    studyHeader.style.paddingLeft = smallerPaddingLeft
  }
}
