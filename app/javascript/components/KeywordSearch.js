import React, { Component } from 'react';
import Button from 'react-bootstrap/lib/Button';
import InputGroup from 'react-bootstrap/lib/InputGroup';
import Form from 'react-bootstrap/lib/Form';
import { faSearch } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";


class KeyWordSearch extends React.Component{
  constructor(props){
    super(props);
    this.handleSubmit = this.handleSubmit.bind(this)
    this.state = {
      searchTerms: undefined,
    };
  };

  handleSubmit(e){
    // Prevent full page reload
    e.preventDefault();
    console.log(e.target.elements)
    const searchTerm = e.target.elements.searchText.value.trim();
    if(searchTerm){
      // Need to check if search terms are empty and if prevstate is different
      // From current state
      this.setState(()=>{
        return {
          searchTerms:searchTerm
        };

      });
      this.props.updateKeyword(searchTerm);
    }
  }

  render(){
    return(
      <div>
      <Form onSubmit = {this.handleSubmit}>
        <InputGroup>
          <input 
          type="text" 
          placeholder="Enter keyword" 
          name="searchText"/>
            <Button className="search-button" onClick={this.handleSubmit}>
              <FontAwesomeIcon icon={faSearch} />
            </Button>
        </InputGroup>
      </Form>
      </div>
     
    );
  }
}



export default KeyWordSearch;
