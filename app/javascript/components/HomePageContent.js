import React, { Component, useState, useEffect } from 'react';
import SearchPanel from './SearchPanel';
import ResultsPanel from './ResultsPanel';

class HomePageContent extends React.Component{
    constructor(){
        super()
        this.state = {
            results :undefined,
            keyword : null,
            type:'study',
            facets: {},
        };
    }

    fetchResults=(keyword)=>{
        console.log(keyword)
        fetch(`http://localhost:3000/single_cell/api/v1/search?type=${this.state.type}&terms=${keyword}`, {
            headers: {
                'Accept': 'application/json'
              }})
        .then((studyResults)=>{
            console.log(studyResults)
            return studyResults.json()
        }).then(studiesdata => {
            this.setState({
                results:studiesdata,
                keyword:keyword,
            })
            console.log(studiesdata)
        })
    }

    handleKeywordUpdate = (keyword)=>{
        this.setState({keyword}, () =>{this.fetchResults(keyword)})
    }

    componentWillMount(){
        // Get intial studies
        fetch(`http://localhost:3000/single_cell/api/v1/search?type=study`, {
            headers: {
                'Accept': 'application/json',
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
                {console.log(this.state.results)}
            {this.state.results && <ResultsPanel results={this.state.results}/>}
            </div>

        )
    }
}

// function HomePageContent(){
//     const [results, setResults] = useState('');
//     const [keyword, setKeyword] = useState('');
//     const [type] = useState('study');
//     const [facets] = useState({});

//     const fetchResults = (keyword) =>{
//         fetch('http://localhost:3000/single_cell/api/v1/search', {
//             headers: {
//                 'Accept': 'application/json',
//                 params: {
//                     type: type,
//                     terms: keyword,
//                   }
//               }})
//         .then((studyResults)=>{
//             return studyResults.json()
//         }).then(studiesdata => {
//             setResults(studiesdata)
//         })
//     };

//     const handleKeywordUpdate = (keyword) => {
//         setKeyword(keyword, () => {fetchResults(keyword)})
//             }

//     useEffect( () => {
//         async function fetchData() {
//             const res = await fetch('http://localhost:3000/single_cell/api/v1/search', {
//                 headers: {
//                     'Accept': 'application/json',
//                     params: {
//                         type: type,
//                         terms: keyword,
//                       }
//                   }});
//                   // Pull out the data as usual
//             const json = await res.json();

//             // Save the posts into state
//             // (look at the Network tab to see why the path is like this)
//             setResults(json)
//         }
//         fetchData()
//       }, [results, setResults]);

//     return (
//         <div>
//             <SearchPanel updateKeyword={handleKeywordUpdate}/>
//             <ResultsPanel results={results}/>
//             </div>
//     )
// }

export default HomePageContent;
