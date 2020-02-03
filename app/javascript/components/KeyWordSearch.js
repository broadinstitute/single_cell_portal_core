import React, { Component } from 'react';
import Button from 'react-bootstrap/Button';
import InputGroup from 'react-bootstrap/InputGroup';
import TabContainer from 'react-bootstrap/TabContainer';
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';
import TabContent from 'react-bootstrap/TabContent'
import FormControl from 'react-bootstrap/FormControl';


class KeyWordSearch extends React.Component{
  render(){
    return(
      <div>
      <InputGroup>
        <FormControl placeholder="Enter Keyword"/>
        <Button>
            <span>Search</span>
        </Button>
      </InputGroup>
      </div>
     
    );
  }
}



export default KeyWordSearch;