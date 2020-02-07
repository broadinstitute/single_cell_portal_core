import React, { Component } from 'react';
import SearchPanel from './SearchPanel'
import ResultsPanel from '.ResultsPanel'

class HomePageContent extends React.Component{
    constructor(){
        super()
        this.fetchResults= this.fetchResults.bind(this);
        this.state = {
            results :undefined,
            keyword : "",
            type:study,
            facets: {},
        };
    }

    fetchResults=(keyword)=>{
        fetch(`http://localhost:3000/single_cell/api/v1/search?type=${this.state.type}&${this.state.keyword}`, {
            headers: {
                'Accept': 'application/json'
              }})
        .then((studyResults)=>{
            console.log(studyResults)
            return studyResults.json()
        }).then(studiesdata => {
            this.setState({results:studiesdata})
            console.log(studiesdata)
        })
    }

    handleKeywordUpdate = (keyword)=>{
        this.setState({keyword}, () =>{this.fetchResults(keyword)})
    }

    componentWillMount(){
        // Get intial studies
        fetch('http://localhost:3000/single_cell/api/v1/search?type=study', {
            method:"GET",
            headers: {  
            'Accept': 'application/json'
          }})
        .then((studyResults)=>{
            return studyResults.json()
        }).then(studiesdata => {
            this.setState({results:studiesdata})
        })

    }

    render(){
        return(
            <div>
            <SearchPanel updateKeyword={this.handleKeywordUpdate}/>
            <ResultsPanel results={this.state.results}/>
            </div>

        )
    }
}