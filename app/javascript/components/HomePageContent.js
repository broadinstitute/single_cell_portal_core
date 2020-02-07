import React, { Component } from 'react';
import SearchPanel from './SearchPanel'
import ResultsPanel from '.ResultsPanel'

class HomePageContent extends React.Component{
    constructor(){
        super()
        this.state = {
            results :[],
            keyword : "",
            type:"",
            facets: {},
        };
    }

    fetchResults=()=>{
        fetch('http://localhost:3000/single_cell/api/v1/search?type=study', {
            headers: {
                "Content-type": "application/json; charset=UTF-8"
              }})
        .then((studyResults)=>{
            return studyResults.json()
        }).then(studiesdata => {
            this.setState({results:studiesdata})
            console.log(studiesdata)
        })
    }

    handleKeywordUpdate(keyword){
        console.log(keyword)
        // this.setState({keyword:keyword}, this.fetchResults)
    }

    componentWillMount(){
        fetch('http://localhost:3000/single_cell/api/v1/search?type=study', {
            method:"GET",
            headers: {  
            'Accept': 'application/json'
          }})
        .then((studyResults)=>{
            return studyResults.json()
        }).then(studiesdata => {
            this.setState({results:studiesdata})
            console.log(studiesdata)
        })

    }

    render(){
        return(
            <div>
            <SearchPanel updateKeyword={this.handleKeywordUpdate}/>
            <ResultsPanel/>
            </div>

        )
    }
}