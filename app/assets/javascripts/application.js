// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery_ujs
//= require jquery-ui/effect
//= require jquery-ui/effect-highlight
//= require ckeditor/init
//= require dataTables/jquery.dataTables
//= require dataTables/bootstrap/3/jquery.dataTables.bootstrap
//= require jquery-fileupload
//= require jquery-fileupload/basic-plus
//= require jquery_nested_form
//= require jquery-ui/datepicker
//= require spin.min
//= require_tree .

var fileUploading = false;

// toggle chevron glyphs on clicks
function toggleGlyph(el) {
    el.toggleClass('fa-chevron-right fa-chevron-down');
}

// attach various handlers to bootstrap items and turn on functionality
$(function() {
    $('.panel-collapse').on('show.bs.collapse hide.bs.collapse', function() {
        toggleGlyph($(this).prev().find('span.toggle-glyph'));
    });

    $('[data-toggle="tooltip"]').tooltip({container: 'body'});
    $('[data-toggle="popover"]').popover();
});

// toggle the Search/View options panel
function toggleSearch() {
    $('#search-target').toggleClass('col-md-3 hidden');
    $('#render-target').toggleClass('col-md-9 col-md-12');
    $('#search-options-panel').toggleClass('hidden');
    $('#show-search-options').toggleClass('hidden');
    if ( $('#show-search-options').css('display') == 'none' ) {
        $('#show-search-options').tooltip('hide');
    }
    // trigger resizeEnd to re-render Plotly to use available space
    setTimeout(function() {
        $(window).trigger('resizeEnd');
    }, 100);
}

// options for Spin.js
var opts = {
    lines: 13 // The ~number of lines to draw
    , length: 56 // The length of each line
    , width: 14 // The line thickness
    , radius: 42 // The radius of the inner circle
    , scale: 1 // Scales overall size of the spinner
    , corners: 1 // Corner roundness (0..1)
    , color: '#000' // #rgb or #rrggbb or array of colors
    , opacity: 0.25 // Opacity of the lines
    , rotate: 0 // The rotation offset
    , direction: 1 // 1: clockwise, -1: counterclockwise
    , speed: 1 // Rounds per second
    , trail: 60 // Afterglow percentage
    , fps: 20 // Frames per second when using setTimeout() as a fallback for CSS
    , zIndex: 2e9 // The z-index (defaults to 2000000000)
    , className: 'spinner' // The CSS class to assign to the spinner
    , top: '50%' // Top position relative to parent
    , left: '50%' // Left position relative to parent
    , shadow: false // Whether to render a shadow
    , hwaccel: false // Whether to use hardware acceleration
    , position: 'absolute' // Element positioning
};

var smallOpts = {
    lines: 11, // The number of lines to draw
    length: 9, // The length of each line
    width: 3, // The line thickness
    radius: 4, // The radius of the inner circle
    scale: 1 // Scales overall size of the spinner
    , corners: 1 // Corner roundness (0..1)
    , color: '#000' // #rgb or #rrggbb or array of colors
    , opacity: 0.25 // Opacity of the lines
    , rotate: 0 // The rotation offset
    , direction: 1 // 1: clockwise, -1: counterclockwise
    , speed: 1 // Rounds per second
    , trail: 60 // Afterglow percentage
    , fps: 20 // Frames per second when using setTimeout() as a fallback for CSS
    , zIndex: 2e9 // The z-index (defaults to 2000000000)
    , className: 'spinner' // The CSS class to assign to the spinner
    , top: '7px' // Top position relative to parent
    , left: '50%' // Left position relative to parent
    , shadow: false // Whether to render a shadow
    , hwaccel: false // Whether to use hardware acceleration
    , position: 'relative' // Element positioning
};

// launch a modal spinner whenever a select changes that will take more than a few seconds
$(function() {
   $('.spin').change(function(){
        var target = $('#spinner_target')[0];
        new Spinner(opts).spin(target);
        $('#loading-modal').modal('show');
    });
});

// launch a small spinner on elements with 'loading' class
$(function() {
    $('.loading').click(function(){
        var target = $('#spinner_target')[0];
        new Spinner(opts).spin(target);
        $('#loading-modal').modal('show');
    });
});

// default title font settings for axis titles in plotly
var plotlyTitleFont = {
    family: 'Helvetica Neue',
    size: 16,
    color: '#333'
};

// default label font settings for colorbar titles in plotly
var plotlyLabelFont = {
    family: 'Helvetica Neue',
    size: 12,
    color: '#333'
};

var plotlyDefaultLineColor = 'rgb(40, 40, 40)';

// default scatter plot colors, a combination of colorbrewer sets 1-3
var colorBrewerSet = [];
Array.prototype.push.apply(colorBrewerSet, colorbrewer['Set1'][9], colorbrewer['Set2'][8], colorbrewer['Set3'][12]);

// clear out text area in a form
function clearForm(target) {
    $('#' + target).val("");
}

// check if there are blank text boxes or selects
function validateFields(selector) {
    var values = selector.map(function() {return $(this).val()}).get();
    return values.indexOf("") === -1;
}

// check if all checkboxes are checked
function validateChecks(selector) {
    var values = selector.map(function() {return $(this).prop('checked')}).get();
    return values.indexOf(false) === -1;
}

// check if at least one radio is selected in a group
function validateRadios(selector) {
    var values = selector.map(function() {return $(this).prop('checked')}).get();
    return values.indexOf(true) >= 0;
}

// set error state for items that have a property of 'checked' == false
function setErrorOnChecked(selector) {
    selector.map(function() {
        if ( !$(this).prop('checked') ) {
            $(this).parent().addClass('has-error has-feedback');
        } else {
            $(this).parent().removeClass('has-error has-feedback');
        }
    });
}

// set error state on blank text boxes or selects
function setErrorOnBlank(selector) {
    selector.map(function() {
        if ( $(this).val() == "" ) {
            $(this).parent().addClass('has-error has-feedback');
        } else {
            $(this).parent().removeClass('has-error has-feedback');
        }
    });
}

// custom event to trigger resize event only after user has stopped resizing the window
$(window).resize(function() {
    if(this.resizeTO) clearTimeout(this.resizeTO);
    this.resizeTO = setTimeout(function() {
        $(this).trigger('resizeEnd');
        console.log('resizeEnd');
    }, 100);
});

// generic function to render Morpheus
function renderMorpheus(dataPath, annotPath, target, fitType) {
    $(target).empty();
    var config = {dataset: dataPath, el: $(target)};

    // fit rows, columns, or both to screen
    if (fitType == 'cols') {
        config.columnSize = 'fit';
    } else if (fitType == 'rows') {
        config.rowSize = 'fit';
    } else if (fitType == 'both') {
        config.columnSize = 'fit';
        config.rowSize = 'fit';
    }

    // load annotations if specified
    if (annotPath != '') {
        config.columnAnnotations = [{
            file : annotPath,
            datasetField : 'id',
            fileField : 'CELL_NAME'}
        ];
        config.columnSortBy = [
            {field:'CLUSTER', order:0},
            {field:'SUB-CLUSTER', order:0}
        ];
    }

    // instantiate heatmap and embed in DOM element
    new morpheus.HeatMap(config);

}

// helper to compute color gradient scales using chroma.js for sub-cluster members
function computeColorScale(clusterColor, clusters) {
    // check brightness to know which direction to scale colors
    var start = chroma(clusterColor);
    if (start.luminance() > 0.5) {
        return chroma.scale([clusterColor, start.darken(clusters / 2).saturate(clusters / 2)]).colors(clusters);
    } else {
        return chroma.scale([start.brighten(clusters / 2).desaturate( clusters / 2), clusterColor]).colors(clusters);
    }

}

// toggles visibility and disabled status of file upload and fastq url fields
function toggleFastqFields(target) {
    var fileField = $("#" + target).find('.upload-field');
    $(fileField).toggleClass('hidden');
    var fastqField = $("#" + target).find('.fastq-field');
    $(fastqField).toggleClass('hidden');
    // toggle disabled status by returning inverse of current state
    $(fastqField).find('input').attr('disabled', !$(fastqField).find('input').is('[disabled=disabled]'));
    // set human data attr to true
    var humanData = $(fastqField).find('input[type=hidden]');
    $(humanData).val($(humanData).val() == 'true' ? 'false' : 'true' );
    // enable name field & update button to allow saving
    var saveBtn = $('#' + target).find('.save-study-file');
    $(saveBtn).attr('disabled', !$(saveBtn).is('[disabled=disabled]'));
    var nameField = $('#' + target).find('.filename');
    $(nameField).attr('readonly', !$(nameField).is('[readonly=readonly]'));
    $(nameField).attr('placeholder', '');
    // animate highlight effect to show fields that need changing
    $(nameField).parent().effect('highlight', 1200);
    $(fastqField).effect('highlight', 1200);
}