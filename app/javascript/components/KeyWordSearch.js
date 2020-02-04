import React, { Component } from 'react';
import Button from 'react-bootstrap/Button';
import InputGroup from 'react-bootstrap/InputGroup';
import Form from 'react-bootstrap/Form';


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

    const searchTerm = e.target.elements.searchText.value.trim();
    if(searchTerm){
      // Need to check if search terms are empty and if prevstate is different
      // From current state
      this.setState(()=>{
        return {
          searchTerms:searchTerm
        };

      });
      this.setState((prevState)=>{
        return {
          searchTerms:prevState.searchTerms
        };

      });
    }
  }

  render(){
    return(
      <div>
      <Form onSubmit = {this.handleSubmit}>
        <InputGroup>
          <input 
          type="text" 
          placeholder="Enter Keyword" 
          name="searchText"/>
            <Button class="input-group-append" onClick={this.handleSubmit}><span>Search</span>
            </Button>
        </InputGroup>
      </Form>
      </div>
     
    );
  }
}



export default KeyWordSearch;