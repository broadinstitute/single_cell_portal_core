import React, { Component, useState, useEffect } from 'react';
import SearchPanel from './SearchPanel';
import ResultsPanel from './ResultsPanel';


export default function HomePageContent(){
    const [results, setResults] = useState('');
    const [keyword, setKeyword] = useState('');
    const [type] = useState('study');
    const [facets] = useState({});

    const handleKeywordUpdate = (keyword) => {
        setKeyword(keyword)
            }

    useEffect( () => {
       fetch(`http://localhost:3000/single_cell/api/v1/search?type=${type}&terms=${keyword}`, {
                headers: {
                    'Accept': 'application/json',
                }})
                  .then((studyResults)=>{
                                return studyResults.json()
                            }).then(data =>setResults(data))}, [keyword]);

    return (
        <div>
                <SearchPanel updateKeyword={handleKeywordUpdate}/>
            {results && <ResultsPanel results={results}/>}
            </div>
    )
}

