import React from 'react';
import Accordion from 'react-bootstrap/Accordion';
import Card from 'react-bootstrap/Card';

import Filters from './Filters';

export default function FacetsAccordion(props) {
  return (
    // Accordions provide a way to restrict Card components to only open one at a time.
    // https://react-bootstrap.github.io/components/accordion/
    <Accordion defaultActiveKey="0">
      {
        props.facets.map((facet, i) => {
          return (
            <Card>
              <Card.Header>
                <Accordion.Toggle as={Card.Header} variant="link" eventKey={i}>
                  {facet.name}
                </Accordion.Toggle>
              </Card.Header>
              <Accordion.Collapse eventKey={i}>
                <Card.Body>
                  <Filters facet={facet} />
                </Card.Body>
              </Accordion.Collapse>
            </Card>
          );
        })
      }
    </Accordion>
  );
}
