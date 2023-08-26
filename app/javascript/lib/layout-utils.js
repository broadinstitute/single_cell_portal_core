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
export function getGlobalHeaderEndWidth(text, font, extraWidth) {
  const baseWidth = 252 + extraWidth // Width of top-right "Help", "Create study", icons, padding, etc.
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

/** Add tooltip to header for study title, e.g. when it gets truncated */
function addStudyTitleTooltip(studyHeader, titleText) {
  if (studyHeader.hasAttribute('data-toggle')) {return}

  // Show tooltip for especially long cases
  studyHeader.setAttribute('data-toggle', 'tooltip')
  studyHeader.setAttribute('data-original-title', titleText)

  // Ensure tooltip doesn't get cut off from above
  studyHeader.setAttribute('data-placement', 'bottom')
}

/** Remove tooltip from header for study title, e.g. when it *not* truncated */
function removeStudyTitleTooltip(studyHeader) {
  if (!studyHeader.hasAttribute('data-toggle')) {return}
  studyHeader.removeAttribute('data-toggle')
  studyHeader.removeAttribute('data-original-title')
  studyHeader.removeAttribute('data-placement')
}

/** Slightly decrease size of font and left padding */
function shrinkStudyTitle(studyHeader) {
  // Decrease font size by 1px and padding at left by 1/2 original
  const fontSize = pxToNumber(getStyle(studyHeader, 'font-size')) // e.g. '14px' -> 14
  const smallerFontSize = `${fontSize - 1}px`
  studyHeader.style.fontSize = smallerFontSize
  const paddingLeft = pxToNumber(getStyle(studyHeader, 'padding-left'))
  const smallerPaddingLeft = `${paddingLeft / 2}px`
  studyHeader.style.paddingLeft = smallerPaddingLeft
}

/** Undo `shrinkStudyTitle` */
function unshrinkStudyTitle(studyHeader) {
  studyHeader.removeAttribute('style')
}

/** Determine if study title has x-overflow in study header container */
function getIsTitleTruncated(studyHeader) {
  const studyHeaderWidth = studyHeader.clientWidth
  const titleText = studyHeader.innerText
  const titleFont = getStyle(studyHeader, 'font')
  const studyTitleWidth = getTextSize(titleText, titleFont).width

  const isTitleTruncated = studyTitleWidth > studyHeaderWidth

  return isTitleTruncated
}

/**
 * Mitigate truncation edge case for very long titles
 *
 * If study title is smaller than its container, and user's screen is basically maximized,
 * then slightly decrease font size of study title, and slightly enlarge container.
 */
export function mitigateStudyOverviewTitleTruncation() {
  if (window.SCP.analyticsPageName !== 'site-study') {return}

  const studyHeader = document.querySelector('.study-header')
  const titleText = studyHeader.innerText
  const isTruncated = getIsTitleTruncated(studyHeader)
  if (isTruncated) {
    if (!studyHeader.hasAttribute('style')) {shrinkStudyTitle(studyHeader)}
    const isStillTruncated = getIsTitleTruncated(studyHeader)
    if (isStillTruncated) {
      addStudyTitleTooltip(studyHeader, titleText)
    }
  } else {
    if (studyHeader.hasAttribute('style')) {
      unshrinkStudyTitle(studyHeader)
      const isNowTruncated = getIsTitleTruncated(studyHeader)
      if (isNowTruncated) {
        shrinkStudyTitle(studyHeader)
      }
    }
    removeStudyTitleTooltip(studyHeader)
  }

  const jqStudyHeader = $('.study-header')
  if (jqStudyHeader.tooltip) {jqStudyHeader.tooltip('hide')}
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
  const signInIcon = document.getElementById('#login-nav .fa-sign-in-alt')
  const signInIconWidth = signInIcon?.clientWidth ?? 0
  const minWidth = getGlobalHeaderEndWidth(userOrSignInText, font, signInIconWidth)
  globalHeaderEnd.style.minWidth = `${minWidth}px`

  // Mitigate truncation edge case for very long titles
  //
  // If study title is smaller than its container
  // then slightly decrease font size of study title, and slightly enlarge container.
  mitigateStudyOverviewTitleTruncation()
}
