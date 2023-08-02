import React from 'react'

export const supportEmailAddress = 'scp-support@broadinstitute.zendesk.com'
export const supportEmailLink = (
  <a href={`mailto:${supportEmailAddress}`}>
    {supportEmailAddress}
  </a>
)

export const contactUsLink = (
  <a href={`mailto:${supportEmailAddress}`}>contact us</a>
)

export const serverErrorEnd = <div>
  Sorry, an error has occurred. Support has been notified. Please try
  again. If this error persists, or you require assistance, please
  contact support at
  <br/>
  {supportEmailLink}
</div>

export const userErrorEnd = <div>
  If you require assistance, please contact support at
  <br/>
  {supportEmailLink}
</div>
