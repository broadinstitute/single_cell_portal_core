/* eslint no-console:0 */
// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.
//
// To reference this file, add <%= javascript_pack_tag 'application' %> to the appropriate
// layout file, like app/views/layouts/application.html.erb

import 'styles/application.scss'

import React from 'react';
import ReactDOM from 'react-dom';
import $ from 'jquery';
import jQuery from 'jquery';
import {Spinner} from 'spin.js';
import 'jquery-ui/ui/widgets/datepicker';
import 'jquery-ui/ui/widgets/autocomplete';
import 'jquery-ui/ui/widgets/sortable';
import 'jquery-ui/ui/widgets/dialog';
import 'jquery-ui/ui/effects/effect-highlight';
import igv from 'igv';
import morpheus from 'morpheus-app';
import Ideogram from 'ideogram';
// Per https://ckeditor.com/docs/ckeditor5/latest/builds/guides/integration/advanced-setup.html#scenario-1-integrating-existing-builds
import ClassicEditor from '@ckeditor/ckeditor5-build-classic';

// Note 'components/HomePageContent' is '/app/javascript/components/HomePageContent.js'
import HomePageContent from 'components/HomePageContent';

document.addEventListener('DOMContentLoaded', () => {
  if (document.getElementById('home-page-content')) {
    ReactDOM.render(
      <HomePageContent />, document.getElementById('home-page-content'),
    )
  }
  if (document.getElementById('scp-search-results-root-element')) {
    ReactDOM.render(
      <ResultsPanel />, document.getElementById('scp-search-results-root-element'),
    )
  }
});

// SCP expects these variables to be global.
window.$ = $;
window.jQuery = jQuery;
window.ClassicEditor = ClassicEditor;
window.Spinner = Spinner;
window.morpheus = morpheus;
window.igv = igv;
window.Ideogram = Ideogram;

// For down the road, when we use ES6 imports in SCP JS app code
// export {$, jQuery, ClassicEditor, Spinner, morpheus, igv, Ideogram};
