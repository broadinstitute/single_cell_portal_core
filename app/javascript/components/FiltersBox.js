import React, { useState, useEffect } from 'react';
import Button from 'react-bootstrap/Button';
import InputGroup from 'react-bootstrap/InputGroup';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faExternalLinkAlt } from '@fortawesome/free-solid-svg-icons';

import FiltersSearchBar from './FiltersSearchBar';

function arraysEqual(a, b) {
  if (a === b) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;

  // If you don't care about the order of the elements inside
  // the array, you should sort both arrays here.
  // Please note that calling sort on an array will modify that array.
  // you might want to clone your array first.

  for (var i = 0; i < a.length; ++i) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

export default function FiltersBox(props) {
  const [canSave, setCanSave] = useState(false);
  const [savedSelection, setSavedSelection] = useState([]);
  const [selection, setSelection] = useState([]);

  useEffect(() => {
    setCanSave(!arraysEqual(selection, savedSelection));
  }, [selection]);

  useEffect(() => {
    setCanSave(false);
  }, [savedSelection]);

  // Systematic, predictable IDs help UX research and UI development.
  //
  // Form of IDs: <general name> <specific name(s)>
  // General name: All lowercase, specified in app code (e.g. 'save-facet', 'filter')
  // Specific name(s): Cased as specified in API (e.g. 'species', 'NCBItaxon9606')
  //
  // UI code concatenates names in the ID.  Names in ID are hyphen-delimited.
  //
  // Examples:
  //   * save-facet-species (for calls-to-action use ID: <action> <component>)
  //   * filter-species-NCBItaxon9606
  const facetName = props.facet.name;
  const componentName = 'filters-box';
  const filtersBoxID = `${componentName}-${facetName}`;
  const saveID = `save-${filtersBoxID}`;

  /**
   * Returns IDs of selected filters.
   * Enables comparing current vs. saved filters
   */
  function getCheckedFilterIDs() {
    const checkedSelector = `#${filtersBoxID} input:checked`;
    const checkedFilterIDs =
      [...document.querySelectorAll(checkedSelector)].map((filter) => {
        return filter.id;
      });
    return checkedFilterIDs
  }

  function handleFilterClick() {
    setSelection(getCheckedFilterIDs());
  }

  function handleSaveClick(event) {
    const saveButtonClasses = Array.from(event.target.classList);
  
    if (saveButtonClasses.includes('disabled')) return;
    
    setSavedSelection(getCheckedFilterIDs());
  };

  return (
    <div class={componentName} id={`${filtersBoxID}`} style={{display: props.show ? '' : 'none'}}>
      <FiltersSearchBar filtersBoxID={filtersBoxID} />
      <p class='filters-box-header'>
        <span class='default-filters-list-name'>FREQUENTLY SEARCHED</span>
        <span class='facet-ontology-links'>
          {props.facet.links.map((link) => {
            return (
              <a href={link.url} target='_blank'>
                {link.name}&nbsp;&nbsp;<FontAwesomeIcon icon={faExternalLinkAlt}/><br/>
              </a>
            );
          })}
        </span>
      </p>
      <ul>
        {props.facet.filters.map((d) => {
          const id = `filter-${facetName}-${d.id}`;
          return (
            <li key={'li-' + id}>
              <InputGroup.Checkbox
                id={id}
                aria-label="Checkbox"
                name={id}
                onClick={handleFilterClick}
              />
              <label htmlFor={id}>{d.name}</label>
            </li>
          );
        })}
      </ul>
      <div class="filters-box-footer">
        <span>Clear</span>
        <Button 
          id={saveID}
          className={'facet-save-button ' + (canSave ? 'enabled' : 'disabled')}
          onClick={handleSaveClick}>
          SAVE
        </Button>
      </div>
    </div>
  );
}