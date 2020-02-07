import React, { Component } from 'react';
import SearchPanel from './SearchPanel'
import ResultsPanel from '.ResultsPanel'

class HomePageContent extends React.Component{
    constructor(){
        super()
        this.state = {
            results = []
        };
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
            <SearchPanel/>
            <ResultsPanel/>
            </div>

        )
    }
}