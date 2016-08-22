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
//= require jquery.bootstrap.wizard
//= require jquery-fileupload
//= require jquery-fileupload/basic-plus
//= require jquery_nested_form
//= require jquery-ui/datepicker
//= require spin.min
//= require_tree .

var fileUploading = false;

// used for keeping track of position in wizard
var completed = {
    initialize_assignments_form_nav: false,
    initialize_clusters_form_nav: false,
    initialize_expression_form_nav: false,
    initialize_sub_clusters_form_nav: false,
    initialize_marker_genes_form_nav: false,
    initialize_fastq_form_nav: false,
    initialize_misc_form_nav: false
};

function completeWizardStep(step) {
    completed[step] = true;
    return completed;
}

function resetWizardStep(step) {
    completed[step] = false;
    $('#' + step + '_completed').html("");
    setWizardProgress(getWizardStatus());
    return completed;
}

// get current status of upload/initializer wizard
function getWizardStatus() {
    var done = 0;
    for (var step in completed) {
        if (completed[step] == true) {
            done++;
        }
    }
    return done;
}

function setWizardProgress(stepsDone) {
    var steps = parseInt(stepsDone);
    var totalSteps = $('li.wizard-nav').length;
    var totalCompletion = Math.round((stepsDone/totalSteps) * 100);
    $('#bar').find('.progress-bar').css({width:totalCompletion+'%'});
    $('#progress-count').html(totalCompletion+'% Completed');
}

function showSkipWarning(step) {
    if (['initialize_assignments_form_nav','initialize_clusters_form_nav','initialize_expression_form_nav'].indexOf(step) >= 0) {
        return (!completed.initialize_assignments_form_nav || !completed.initialize_clusters_form_nav || !completed.initialize_expression_form_nav)
    } else {
        return false;
    }
}

// toggle chevron glyphs on clicks
function toggleGlyph(el) {
    el.toggleClass('fa-chevron-right fa-chevron-down');
}

// attach various handlers to bootstrap items and turn on functionality
$(function() {
    $('.panel-collapse').on('show.bs.collapse hide.bs.collapse', function() {
        toggleGlyph($(this).prev().find('span.toggle-glyph'));
    });

    $('.datepicker').datepicker({dateFormat: 'yy-mm-dd'});

    $('[data-toggle="tooltip"]').tooltip({container: 'body'});
    $('[data-toggle="popover"]').popover();

    // warns user of in progress uploads, fileUploading is set to true from fileupload().add()
    $('.check-upload').click(function() {
        if (fileUploading) {
            if (confirm("You still have file uploads in progress - leaving the page will cancel any incomplete uploads.  " +
                "Click 'OK' to leave or 'Cancel' to stay.  You may open another tab to continue browsing if you wish."))
            {
                return true;
            } else {
                return false;
            }
        }
    });

    // generic warning and spinner for deleting files
    $('.delete-file').click(function() {
        if ( confirm('Are you sure?  This file will be deleted and any associated database records removed.  This cannot be undone.')) {
            var modal = $('#delete-modal');
            var modalTgt = modal.find('.spinner-target')[0];
            var spin = new Spinner(opts).spin(modalTgt);
            $(modalTgt).data('spinner', spin);
            modal.modal('show');
        }
    });
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
    lines: 13, // The number of lines to draw
    length: 56, // The length of each line
    width: 14, // The line thickness
    radius: 42, // The radius of the inner circle
    scale: 1, // Scales overall size of the spinner
    corners: 1, // Corner roundness (0..1)
    color: '#000', // #rgb or #rrggbb or array of colors
    opacity: 0.25, // Opacity of the lines
    rotate: 0, // The rotation offset
    direction: 1, // 1: clockwise, -1: counterclockwise
    speed: 1, // Rounds per second
    trail: 60, // Afterglow percentage
    fps: 20, // Frames per second when using setTimeout() as a fallback for CSS
    zIndex: 2e9, // The z-index (defaults to 2000000000)
    className: 'spinner', // The CSS class to assign to the spinner
    top: '50%', // Top position relative to parent
    left: '50%', // Left position relative to parent
    shadow: false, // Whether to render a shadow
    hwaccel: false, // Whether to use hardware acceleration
    position: 'absolute' // Element positioning
};

var smallOpts = {
    lines: 11, // The number of lines to draw
    length: 9, // The length of each line
    width: 3, // The line thickness
    radius: 4, // The radius of the inner circle
    scale: 1,  // Scales overall size of the spinner
    corners: 1, // Corner roundness (0..1)
    color: '#000',  // #rgb or #rrggbb or array of colors
    opacity: 0.25,  // Opacity of the lines
    rotate: 0, // The rotation offset
    direction: 1, // 1: clockwise, -1: counterclockwise
    speed: 1, // Rounds per second
    trail: 60, // Afterglow percentage
    fps: 20,  // Frames per second when using setTimeout() as a fallback for CSS
    zIndex: 2e9,  // The z-index (defaults to 2000000000)
    className: 'spinner',  // The CSS class to assign to the spinner
    top: '7px',  // Top position relative to parent
    left: '50%',  // Left position relative to parent
    shadow: false,  // Whether to render a shadow
    hwaccel: false,  // Whether to use hardware acceleration
    position: 'relative' // Element positioning
};

// launch a modal spinner whenever a select changes that will take more than a few seconds
$(function() {
   $('.spin').change(function(){
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

// default scatter plot colors, a combination of colorbrewer sets 1-3 with tweaks to the yellow members
var colorBrewerSet = ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#a65628", "#f781bf", "#999999",
    "#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494", "#b3b3b3", "#8dd3c7",
    "#bebada", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5", "#d9d9d9", "#bc80bd", "#ccebc5", "#ffed6f"];

// clear out text area in a form
function clearForm(target) {
    $('#' + target).val("");
}

// check if there are blank text boxes or selects
function validateFields(selector) {
    var values = selector.map(function() {return $(this).val()}).get();
    return values.indexOf("") === -1;
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
        return chroma.scale([start.brighten(clusters / 3).desaturate( clusters / 3), clusterColor]).colors(clusters);
    }

}

// toggles visibility and disabled status of file upload and fastq url fields
function toggleFastqFields(target) {
    var selector = $("#" + target);
    var fileField = selector.find('.upload-field');
    $(fileField).toggleClass('hidden');
    var fastqField = selector.find('.fastq-field');
    $(fastqField).toggleClass('hidden');
    // toggle disabled status by returning inverse of current state
    $(fastqField).find('input').attr('disabled', !$(fastqField).find('input').is('[disabled=disabled]'));
    // set human data attr to true
    var humanData = $(fastqField).find('input[type=hidden]');
    $(humanData).val($(humanData).val() == 'true' ? 'false' : 'true' );
    // enable name field & update button to allow saving
    var saveBtn = selector.find('.save-study-file');
    $(saveBtn).attr('disabled', !$(saveBtn).is('[disabled=disabled]'));
    var nameField = selector.find('.filename');
    $(nameField).attr('readonly', !$(nameField).is('[readonly=readonly]'));
    $(nameField).attr('placeholder', '');
    // animate highlight effect to show fields that need changing
    $(nameField).parent().effect('highlight', 1200);
    $(fastqField).effect('highlight', 1200);
}