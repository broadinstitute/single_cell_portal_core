import React, { Component } from 'react';
import SearchPanel from './SearchPanel'
import ResultsPanel from '.ResultsPanel'

class HomePageContent extends React.Component{
    constructor(){
        super()
        this.handleKeywordUpdate = this.handleKeywordUpdate.bind(this)
        this.state = {
            results :[],
            keyword : "",
            type:"",
            facets: {},
        };
    }

    fetchResults=()=>{
        fetch('https://singlecell.broadinstitute.org/single_cell/api/v1/search?type=study')
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
        fetch('https://singlecell.broadinstitute.org/single_cell/api/v1/search?type=study')
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