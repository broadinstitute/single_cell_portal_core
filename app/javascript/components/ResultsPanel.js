import React from 'react';
import Tab from 'react-bootstrap/lib/Tab';
import Tabs from 'react-bootstrap/lib/Tabs';
import { TabContainer } from 'react-bootstrap';

const ResultsPanel = (props) => {
    
  return( 
    <div id="results-panel">
      <Tab.Container id="result-tabs" defaultActiveKey="study">
          <Tabs defaultActiveKey='study' animation={false} >
            <Tab eventKey='study' title="Studies" >
              <StudyResults results={props.results}/>
            </Tab>   
            <Tab eventKey='files' title='Files'/>   
          </Tabs>
      </Tab.Container>
    </div>
  );

  }

const StudyResults = (props) => {
  var results;
   if(props.results.studies.length>0){
    results = props.results.studies.map((result)=>(
      <div key={result.accession} className='card'>
      <Study  
        study={result}
        handleStudyLabel = {props.handleStudyLabel}
        />
        </div>
            )               
    )
  }else{
   results = <p>No Results</p>
  }

  return(
    <Tab.Content id ='results-content'>
       {results}
        </Tab.Content>);

}

const Study =(props)=> {
  const convertUnicode = (input) => {
    return input.replace(/\\u(\w\w\w\w)/g,function(a,b) {
      var charcode = parseInt(b,16);
      return String.fromCharCode(charcode);
    });
  }
  const  foo =  {__html: props.study.description};

    return(
          <div key={props.study.accession}>
            <label htmlFor={props.study.name} id= 'result-title'>
              <a href={props.study.study_url}>{props.study.name} </a></label>
            <div>
              <span id = 'cell-count'className="badge badge-secondary">{props.study.cell_count} Cells </span>
            </div>
            
            <span dangerouslySetInnerHTML={foo} id='descrition-text-area' disabled accession = {props.study.name}></span>
          </div>
            );
  }

export default ResultsPanel;