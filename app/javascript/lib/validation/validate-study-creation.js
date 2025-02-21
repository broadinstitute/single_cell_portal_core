/** Convert Date string to string format in "Data release date" UI */
function dateToMMDDYYYY(dateString) {
  const date = new Date(dateString)
  const rawMonth = date.getMonth() + 1; // Months are zero-indexed, so add 1
  const rawDay = date.getDate();
  const year = date.getFullYear();

  const month = rawMonth.toString().padStart(2, '0');
  const day = rawDay.toString().padStart(2, '0');

  const MMDDYYYY = `${month}/${day}/${year}`;

  return MMDDYYYY
}

/** Ensure any embargo date is between tomorrow and max embargo date */
export function validateEmbargo() {
  let isValid = true
  let message = ''

  const inputElement = document.querySelector('#study_embargo')
  const rawEmbargoDate = inputElement.value
  const embargoDate = new Date(inputElement.value)
  const maxDate = new Date(inputElement.max)

  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);

  if (
    rawEmbargoDate !== '' &&
    (embargoDate > maxDate || embargoDate < tomorrow)
  ) {
    isValid = false
    const tomorrowFormatted = dateToMMDDYYYY(tomorrow)
    const maxDateFormatted = dateToMMDDYYYY(maxDate)

    message =
      `If embargoed, "Data release date" must be between ` +
      `tomorrow (${tomorrowFormatted}) and ${maxDateFormatted}.`
  }

  return [isValid, message]
}
