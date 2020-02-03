import React, { Component } from 'react';
import Button from 'react-bootstrap/Button';
import InputGroup from 'react-bootstrap/InputGroup';
import TabContainer from 'react-bootstrap/TabContainer';
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';
import TabContent from 'react-bootstrap/TabContent'
import FormControl from 'react-bootstrap/FormControl';



var searchQuery = "This is a search query"
class SearchForm extends React.Component{
  // constructor(text = 'Search'){
  //   this.text =text;
  // }

  // buttonHandler(e){
  //   return this.text
  // }
  // makeRequest()

  render(){
    return(
      <div>
        <p>Studies</p>
        <SearchBar/>
      </div>
      );
     }
}

class SearchBar extends React.Component{
  render(){
    return(
      <div>
      <InputGroup>
        <FormControl placeholder="Enter Keyword"/>
        <InputGroup.Append>
            <span>Search</span>
        </InputGroup.Append>
      </InputGroup>
      </div>
     
    );
  }
}

class Results extends React.Component{
  render(){
    return(<Tabs defaultActiveKey="profile" id="uncontrolled-tab-example">
    <Tab eventKey="studies" title="Studies">
      <p>hello</p>
    </Tab>
    <Tab eventKey="files" title="Files">
    </Tab>
  </Tabs>);

  }
}
const studies = (
  <div>
    <h1>Studies</h1>
      <SearchForm />
    </div>
);
// const searchBar = new SearchBar(
//   searchQuery
// );
// function SearchBar(props){
//   return(<div>
//   <input/>{searchQuery}
//   </div>)
// };

export default SearchForm;