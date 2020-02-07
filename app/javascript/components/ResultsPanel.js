import React from 'react';
import Tab from 'react-bootstrap/lib/Tab';
import Tabs from 'react-bootstrap/lib/Tabs';

const results = [
  {
    type:'study',
    name: 'Single nucleus RNA-seq',
    cell_count: 5426,
    acession: 'SCP1',
    description: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
    url: 'singlecell.broadinstitute.org/single_cell/api/v1/site/studies'
  },
  {
    type:'study',
    name: 'Single nucleus RNA-seq',
    cell_count: 5426,
    acession: 'SCP2',
    description: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
    url: 'singlecell.broadinstitute.org/single_cell/api/v1/site/studies'
  },
  {type:'study',
    name: 'Single nucleus RNA-seq',
    cell_count: 5426,
    acession: 'SCP3',
    description: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {
    type:'study',
    name: 'Single nucleus RNA-seq',
    cell_count: 5426,
    acession: 'SCP4',
    description: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {type:'study',
    name: 'Single nucleus RNA-seq',
    cell_count: 5426,
    acession: 'SCP5',
    description: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
];

class ResultsPanel extends React.Component{
  constructor(props){
    super(props);
    this.state = {
      results: undefined,
      facets : []
    };
    this.handleStudyLabel = this.handleStudyLabel.bind(this);
    };

    handleStudyLabel(studyURL){
      // This eventually will be an API call that will render the associated
      // Study page 
      alert({studyURL})  
    }
    
    showResults(){
      // Function to hande future pagination
    }
    render(){
      
      return(
        <div>
          <Tabs defaultActiveKey='study' transition={false}>
            <Tab eventKey='study' title="Studies" >
              <StudyResults handleStudyLabel = {this.handleStudyLabel} results={this.state.results}/>
            </Tab>   
            <Tab eventKey='files' title='Files'/>       
        </Tabs>
        </div>
  );
  
    }
  }

const StudyResults = (props) => {
  // This component may have state/props where onMount a API call is made
  // to get the initial results on the home page.
  return(
    <Tab.Content>
       { props.results.length &&
          props.results.map((result)=>(
            <Study 
              key={result.acession} 
              study={result}
              handleStudyLabel = {props.handleStudyLabel}
              />
          )
              
          )
        }
        </Tab.Content>);

}
StudyResults.defaultProps = {
  // This may move up to the homepage as a property that's passed into the 
  // ResultsPanel component as the property results
  results: results

}

const Study =(props)=>{
   //There needs to be a handler for when a study is clicked it takes
  // a user to the corresponding study page
    return(
          <div key={props.study.acession}>
            <label for={props.study.name}>
              <a href="url">{props.study.name} </a></label>
            <div>
              <span class="badge badge-secondary">{props.study.cell_count} </span>
            </div>
            <p disabled accession = {props.study.name}>{props.study.description}</p>
          </div>
            );
  }

export default ResultsPanel;