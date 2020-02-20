import React, { useState } from 'react';
import Button from 'react-bootstrap/lib/Button';
import InputGroup from 'react-bootstrap/lib/InputGroup';
import Form from 'react-bootstrap/lib/Form';
import { faSearch } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";


export default function KeywordSearch (props){
  const [searchTerms, setsearchTerms] = useState('');

  const handleSubmit = (event) => {
    // Prevent full page reload
    event.preventDefault();
    const searchTerm = event.target.elements.keywordText.value.trim();
    if(searchTerm){
      // Need to check if search terms are empty and if prevstate is different
      // From current state
      setsearchTerms(searchTerm);
      };
      props.updateKeyword(searchTerm);
    }
  
  return (
    <div id='keyword-search'>
      <Form horizontal onSubmit = {handleSubmit} >
        <InputGroup id='keyword-input-group'>
          <input
            id="keyword-input"
            type="text" 
            placeholder="Enter Keyword" 
            name="keywordText"/>
            <div id='keyword-submit'>
            <Button  type='submit'>
              <FontAwesomeIcon icon={faSearch} />
            </Button>
            </div>
        </InputGroup>
      </Form>
    </div>
   
  );
}
