/* eslint-disable */

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
//= require jquery
//= require jquery_ujs
//= require dataTables/jquery.dataTables
//= require dataTables/bootstrap/3/jquery.dataTables.bootstrap
//= require jquery.bootstrap.wizard
//= require jquery-fileupload
//= require jquery-fileupload/basic-plus
//= require jquery_nested_form
//= require bootstrap-sprockets
//= require jquery.actual.min
//= require papaparse.min
//= require StackBlur
//= require jquery.stickyPanel
//= require clipboard.min
//= require ckeditor

// TODO (SCP-3249): Modernize Morpheus, then remove this
//= require morpheus-external-r
var fileUploading = false;
var PAGE_RENDERED = false;
var OPEN_MODAL = '';
var UNSAFE_CHARACTERS = /[\;\/\?\:\@\=\&\'\"\<\>\#\%\{\}\|\\\^\~\[\]\`]/g;

/**
 * regular expression to sanitize filename on upload; mimics the CarrierWave::SanitizedFile.sanitize_regexp
 * value, which is /[^[:word:]\.\-\+]/ - since this doesn't translate to JS, we use the functionally equivalent form
 */
const FILENAME_SANITIZER = /[^\w\.\-\+]/g

// 1: open, -1: closed.
// Upon clicking nav toggle, state multiples by -1, toggling this register value
var exploreMenusToggleState = {
  left: -1,
  right: -1
};

// allowed file extension for upload forms
var ALLOWED_FILE_TYPES = {
    expression: /(\.|\/)(txt|text|mm|mtx|tsv|csv)(\.gz)?$/i,
    plainText: /(\.|\/)(txt|text|tsv|csv)(\.gz)?$/i,
    primaryData: /((\.(fq|fastq)(\.tar)?\.gz$)|\.bam)/i,
    bundled: /(\.|\/)(txt|text|tsv|csv|bam\.bai)(\.gz)?$/i,
    miscellaneous: /(\.|\/)(txt|text|tsv|csv|jpg|jpeg|png|pdf|doc|docx|xls|xlsx|ppt|pptx|zip|loom|h5|h5ad|h5an|ipynb|Rda|rda|Rds|rds)(\.gz)?$/i
};

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

var paginationOpts = {
    lines: 11, // The number of lines to draw
    length: 15, // The length of each line
    width: 5, // The line thickness
    radius: 10, // The radius of the inner circle
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
    top: '12px',  // Top position relative to parent
    left: '50%',  // Left position relative to parent
    shadow: false, // Whether to render a shadow
    hwaccel: false, // Whether to use hardware acceleration
    position: 'relative' // Element positioning
};

// global config for CKEditor instances
var fullCKEditorConfig = {
  alignment: {
    options: [ 'left', 'center', 'right' ]
  },
  image: {
    styles: [
      'full', 'alignLeft', 'alignCenter', 'alignRight'
    ],
    toolbar: [
      'imageStyle:full', 'imageStyle:alignLeft', 'imageStyle:alignCenter', 'imageStyle:alignRight'
    ]
  },
  toolbar: ['heading', '|', 'removeFormat', '|',  'bold', 'italic', 'underline', 'link', 'bulletedList', 'numberedList',
      'blockQuote', '|', 'alignment', 'outdent', 'indent', '|', 'ImageUpload', '|', 'insertTable', 'tableColumn',
      'tableRow', 'mergeTableCells', '|', 'undo', 'redo']
}

$(document).on('shown.bs.modal', function(e) {
    console.log("modal " + $(e.target).attr('id') + ' opened');
    OPEN_MODAL = $(e.target).attr('id');
});

$(document).on('hidden.bs.modal', function(e) {
    console.log("modal " + $(e.target).attr('id') + ' closed');
    OPEN_MODAL = '';
});

function elementVisible(element) {
    return $(element).is(":visible");
}

// used for keeping track of position in wizard
var completed = {
    initialize_raw_expression_form_nav: false,
    initialize_processed_expression_form_nav: false,
    initialize_metadata_form_nav: false,
    initialize_ordinations_form_nav: false,
    initialize_labels_form_nav: false,
    initialize_marker_genes_form_nav: false,
    initialize_primary_data_form_nav: false,
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
        if (completed[step] === true) {
            done++;
        }
    }
    return done;
}

function setWizardProgress(stepsDone) {
    var steps = parseInt(stepsDone);
    var totalSteps = $('li.wizard-nav').length;
    var totalCompletion = Math.round((steps/totalSteps) * 100);
    $('#bar').find('.progress-bar').css({width:totalCompletion+'%'});
    $('#progress-count').html(totalCompletion+'% Completed');
}

// toggle chevron glyphs on clicks
function toggleGlyph(el) {
    el.toggleClass('fa-chevron-right fa-chevron-down');
}

// function to delegate delete call for a file after showing confirmation dialog
function deletePromise(event, message) {
    new Promise(function (resolve) {
        var conf = confirm(message);
        if ( conf === true ) {
            launchModalSpinner('#delete-modal-spinner','#delete-modal', function() {
                return resolve(true);
            });
        } else {
            return resolve(false);
        }
    }).then(function (answer) {
        if (answer !== true) {
            event.stopPropagation();
            event.preventDefault();
        }
        return answer;
    });
}

// attach various handlers to bootstrap items and turn on functionality
function enableDefaultActions() {
    // need to clear previous listener to prevent conflict
    $('.panel-collapse').off('show.bs.collapse hide.bs.collapse');

    $('.panel-collapse').on('show.bs.collapse hide.bs.collapse', function () {
        toggleGlyph($(this).prev().find('span.toggle-glyph'));
    });

    $('body').tooltip({selector: '[data-toggle="tooltip"]', container: 'body', trigger: 'hover'});

    enableHoverPopovers();

    // warns user of in progress uploads, fileUploading is set to true from fileupload().add()
    $('.check-upload').click(function () {
        if (fileUploading) {
            if (confirm("You still have file uploads in progress - leaving the page will cancel any incomplete uploads.  " +
                    "Click 'OK' to leave or 'Cancel' to stay.  You may open another tab to continue browsing if you wish.")) {
                return true;
            } else {
                return false;
            }
        }
    });

    // handler for file deletion clicks, need to grab return value and pass to window
    $('body').on('click', '.delete-file', function (event) {
        deletePromise(event, 'Are you sure?  This file will be deleted and any associated database records removed.  This cannot be undone.');
    });

    // handler for file unsync clicks, need to grab return value and pass to window
    $('body').on('click', '.delete-file-sync', function (event) {
        deletePromise(event, 'Are you sure?  This will remove any database records associated with this file.  This cannot be undone.');
    });

    // disable mousewheel on a input number field when in focus
    // (to prevent Cromium browsers change the value when scrolling)
    $('form').on('focus', 'input[type=number]', function (e) {
        $(this).on('mousewheel.disableScroll', function (e) {
            e.preventDefault()
        });
    });

    $('form').on('blur', 'input[type=number]', function (e) {
        $(this).off('mousewheel.disableScroll')
    });

    // reset units dropdown based on is_raw_counts?
    $('body').on('click', '.raw-counts-radio', function() {
      const exprFields = $(this).closest('.expression-file-info-fields')
      const isRawCounts = exprFields.find('.is_raw_counts_true')[0].checked
      const unitSelect = exprFields.find('.counts-unit-dropdown')
      const unitsSelectDiv = exprFields.find('.raw-counts-units-select')
      const assnSelectDiv = exprFields.find('.raw_associations_select')
      if ( !isRawCounts ) {
        unitSelect.val('');
        setElementsEnabled(unitSelect, false);
        assnSelectDiv.removeClass('hidden')
        unitsSelectDiv.addClass('hidden')
      } else {
        setElementsEnabled(unitSelect, true);
        unitsSelectDiv.removeClass('hidden')
        assnSelectDiv.addClass('hidden')
      }
    });

    // when clicking the main study view page tabs, update the current URL so that when you refresh the tab stays open
    $('#study-tabs').on('shown.bs.tab', function(event) {
        var href = $(event.target).attr('href');
        // use HTML5 history API to update the url without reloading the DOM
        history.pushState('', document.title, href);
    });

}

function enableHoverPopovers(selector='[data-toggle="popover"]') {
    $(selector).popover({container: 'body', html: true, trigger: 'manual'})
        .on("mouseenter", function () {
            var _this = this;
            $(this).popover("show");
            $(".popover").on("mouseleave", function () {
                $(_this).popover('hide');
            });
        }).on("mouseleave", function () {
            var _this = this;
            setTimeout(function () {
                if (!$(".popover:hover").length) {
                    $(_this).popover("hide");
                }
            }, 100);
        });
}


var stickyOptions = {
    topPadding: 85
};

// functions to show loading modals with spinners
// callback function will execute after modal completes opening
function launchModalSpinner(spinnerTarget, modalTarget, callback) {

    // set listener to fire callback, and immediately clear listener to prevent multiple requests queueing
    $(modalTarget).on('shown.bs.modal', function() {
        $(modalTarget).off('shown.bs.modal');
        callback();
    });

    $(spinnerTarget).empty();
    var target = $(spinnerTarget)[0];
    var spinner = new Spinner(opts).spin(target);
    $(target).data('spinner', spinner);
    $(modalTarget).modal('show');
}

// function to close modals with spinners launched from launchModalSpinner
// callback function will execute after modal completes closing
function closeModalSpinner(spinnerTarget, modalTarget, callback) {
    // set listener to fire callback, and immediately clear listener to prevent multiple requests queueing
    $(modalTarget).on('hidden.bs.modal', function() {
        $(modalTarget).off('hidden.bs.modal');
        callback();
    });
    $(spinnerTarget).data('spinner').stop();
    $(modalTarget).modal('hide');
}

// handles showing/hiding main message_modal and cleaning up state on full & partial page renders
function showMessageModal(notice=null, alert=null) {
    // close any open modals
    if (OPEN_MODAL) {
        var modalTarget = $('#' + OPEN_MODAL);
        var modalData = modalTarget.data('bs.modal');
        if ( typeof modalData !== 'undefined' && modalData.isShown) {
            modalTarget.modal("hide");
        }
    }

    var noticeElement = $('#notice-content');
    var alertElement = $('#alert-content');
    if (notice) {
        noticeElement.html(notice);
    } else {
        noticeElement.empty();
    }
    if (alert) {
        alertElement.html("<strong>" + alert + "</strong>");
        // also log alert content to Mixpanel
        window.SCP.log('error-modal', {text: alert})
    } else {
        alertElement.empty();
    }

    if (notice || alert) {
        $("#message_modal").modal("show");
    }

    // don't timeout alert messages, but don't clear if nothing was shown
    if (!alert && notice) {
        setTimeout(function() {
            $("#message_modal").modal("hide");
        }, 3000);
    }
}

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

// set error state on blank text boxes or selects
function setErrorOnBlank(selector) {
    selector.map(function() {
        if ( $(this).val() === "" ) {
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
    }, 100);
});

// toggles visibility and disabled status of file upload and fastq url fields
function toggleFastqFields(target, state) {
    var selector = $("#" + target);
    var fileField = $(selector.find('.upload-field'));
    var fastqField = $(selector.find('.fastq-field'));
    var humanData = $(fastqField.find('input[type=hidden]'));
    var saveBtn = $(selector.find('.save-study-file'));
    var nameField = $(selector.find('.filename'));
    if (state) {
        fileField.addClass('hidden');
        fastqField.removeClass('hidden');
        fastqField.find('input').attr('disabled', false);
        humanData.val('true' );
        saveBtn.attr('disabled', false);
        nameField.attr('readonly', false);
        nameField.attr('placeholder', '');
    } else {
        fileField.removeClass('hidden');
        fastqField.addClass('hidden');
        fastqField.find('input').attr('disabled', 'disabled');
        humanData.val('false');
        if ( selector.find('.upload-fastq').length !== 0 ) {
            saveBtn.attr('disabled', true); // disable save only if file hasn't been uploaded
        }
        nameField.attr('readonly', true);
        nameField.attr('placeholder', 'Filename is taken from uploaded file...');
    }
    // animate highlight effect to show fields that need changing
    nameField.parent().effect('highlight', 1200);
    fastqField.effect('highlight', 1200);
}

// function to return a plotly histogram data object from an array of input values
function formatPlotlyHistogramData(valuesHash, offset) {
    var dataArray = [];
    var i = offset;
    if (i === undefined) {
        i = 0;
    }
    $.each(valuesHash, function(keyName, distData) {
        var trace = {
            x: distData,
            type: 'histogram',
            name: keyName,
            histnorm: '',
            autobinx: false,
            xbins: {
                start: Math.min.apply(Math, distData) - 0.5,
                end: Math.max.apply(Math, distData) + 0.5,
                size: 1
            },
            marker: {
                color: colorBrewerSet[i]
            }
        };
        dataArray.push(trace);
        i++;
    });
    return dataArray;
}

// load column totals for bar charts
function loadBarChartAnnotations(plotlyData) {
    var annotationsArray = [];
    for (var i = 0; i < plotlyData[0]['x'].length ; i++){
        var total = 0;
        plotlyData.map(function(el) {
            var c = parseInt(el['y'][i]);
            if (isNaN(c)) {
                c = 0;
            }
            total += c;
        });
        var annot = {
            x: plotlyData[0]['x'][i],
            y: total,
            text: total,
            xanchor: 'center',
            yanchor: 'bottom',
            showarrow: false,
            font: {
                size: 12
            }
        };
        annotationsArray.push(annot);
    }
    return annotationsArray;
}

// load column totals for scatter charts
function loadScatterAnnotations(plotlyData) {
    var annotationsArray = [];
    var max = 0;
    $(plotlyData).each(function(index, trace) {
        $(trace['y']).each(function(i, el) {
            if (el > max) {max = el};
            var annot = {
                xref: 'x',
                yref: 'y',
                x: plotlyData[index]['x'][i],
                y: el,
                text: el,
                showarrow: false,
                font: {
                    size: 12
                }
            };
            annotationsArray.push(annot);
        });
    });
    // calculate offset at 5% of maximum value
    offset = max * 0.05;
    $(annotationsArray).each(function(index, annotation) {
        // push up each annotation by offset value
        annotation['y'] += offset;
    });
    return annotationsArray;
}

// load bin counts for histogram charts
function loadHistogramAnnotations(plotlyData) {
    var annotationsArray = [];
    var counts = plotlyData[0]['x'];
    $(counts).each(function(i, c) {
        var count = counts.filter(function(a){return (a === c)}).length;
        var annot = {
            x: c,
            y: count,
            text: count,
            xanchor: 'center',
            yanchor: 'bottom',
            showarrow: false,
            font: {
                size: 12
            }
        };
        annotationsArray.push(annot);
    });

    return annotationsArray;
}

// validate uniqueness of entries for various kinds of forms
function validateUnique(formId, textFieldClass) {
    $(formId).find(textFieldClass).change(function() {
        var textField = $(this);
        var newName = textField.val().trim();
        var names = [];
        $(textFieldClass).each(function(index, name) {
            var n = $(name).val().trim();
            if (n !== '') {
                names.push(n);
            }
        });
        // check if there is more than one instance of the new name, this will mean it is a dupe
        if (names.filter(function(n) {return n === newName}).length > 1) {
            alert(newName + ' has already been used.  Please provide a different name.');
            textField.val('');
            textField.parent().addClass('has-error');
        } else {
            textField.parent().removeClass('has-error');
        }
    });
}

// validate a name that will be used as a URL query string parameter (remove unsafe characters)
function validateName(value, selector) {
    if ( value.match(UNSAFE_CHARACTERS) ) {
        alert('You have entered invalid characters for this input: \"' + value.match(UNSAFE_CHARACTERS).join(', ') + '\".  These have been automatically removed from the entered value.');
        sanitizedName = value.replace(UNSAFE_CHARACTERS, '');
        selector.val(sanitizedName);
        selector.parent().addClass('has-error');
        return false
    } else {
        selector.parent().removeClass('has-error');
        return true
    }
}

function validateCandidateUpload(formId, filename, classSelector) {
    var form = $(formId)
    var names = [];
    classSelector.each(function(index, name) {

        var n = $(name).val().trim();
        if (n !== '') {
            names.push(n);
        }
    });
    if (names.filter(function(n) {return n === filename}).length > 1) {
        alert(filename + ' has already been uploaded or is staged for upload.  Please select a different file.');
        return false;
    }
    // enforce species selection
    var taxonSelect = form.find('#study_file_taxon_id')
    if (typeof taxonSelect !== 'undefined' && $(taxonSelect).val() == '') {
        alert('Please select a species before uploading this file.');
        setErrorOnBlank(taxonSelect);
        return false;
    }
    // enforce units if matrix is raw count
    var countsRadio = Array.from(form.find('.raw-counts-radio')).find(radio => radio.checked);
    if ( typeof countsRadio !== 'undefined' && $(countsRadio).val() == '1') {
        var units = form.find('.counts-unit-dropdown');
        if ( $(units).val() == '') {
            alert('You must specify units for raw count matrices.');
            setErrorOnBlank(units);
            return false;
        }
    }
    return true;
}

/**  toggle inline switch and submit associated AJAX form */
function submitToggleForm(toggle) {
    flipToggleSwitch(toggle)
    const formId = $(toggle).data('form-id')
    $(`#${formId}`).submit()
}

/** change toggle display and update associated hidden form input */
function flipToggleSwitch(toggle) {
    const jqToggle = $(toggle)
    const inputId = jqToggle.data('input-id')
    const formField = $(`#${inputId}`)
    const enabled = formField.val() === 'true'
    const toggleState = enabled ? 'off' : 'on'
    const newValue = enabled ? 'false' : 'true'
    formField.val(newValue)
    const toggleText = jqToggle.data(`label-${toggleState}`)
    const newText = `${toggleText} <i class='fas fa-fw fa-toggle-${toggleState}'></i>`
    jqToggle.html(newText)
}

// function to call Google Analytics whenever AJAX call is made
// must be called manually from every AJAX success or js page render
function gaTracker(id){
    $.getScript('https://www.google-analytics.com/analytics.js'); // jQuery shortcut
    window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
    ga('create', id, 'auto');
    ga('send', 'pageview');
}

function gaTrack(path, title) {
    ga('set', { page: path, title: title });
    ga('send', 'pageview');
}

// decode an HTML-encoded string
function unescapeHTML(encodedStr) {
    return $("<div/>").html(encodedStr).text();
}

// validate an email address
function validateEmail(email) {
    var re = /^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;
    return re.test(email);
}

// gather all instances of a given file type from a page
function gatherFilesByType(fileType) {
    var matchingfiles = [];
    $('.file-type').each(function(index, type) {
        if ($(type).val() == fileType) {
            var form = $(type).closest('form');
            var id = $(form).find('#study_file__id').val();
            var name = $(form).find('.filename').val();
            matchingfiles.push({text: name, value: id});
        }
    });
    return matchingfiles;
}

// force login on ajax 401
$(document).ajaxError(function (e, xhr, settings) {
    if (xhr.status === 401) {
        alert('You are not signed in or your session has expired - please login to continue.');
        var url = 'https://' + window.location.hostname + '/single_cell/users/auth/google_oauth2';
        location.href = url;
    }
});

// reopen current tab on page refresh
function reopenUiTab(navTarget) {
    var tab = window.location.hash;
    if (tab !== '') {
        $(navTarget + ' a[href="' + tab + '"]').tab('show');
    }
}

// append a list of options to a select menu dynamically when file_type is changed on sync_study view
// options sourced from gatherFilesByType()
function appendOptionsToDropdown(options, selectElement) {
    var optionsArray = []
    $(options).each(function(index, element) {
        optionsArray.push($('<option />', {
            value: element.value,
            text: element.text
        }));
    });
    selectElement.append(optionsArray);
}

/**
 * dynamically enable/disable click events on DOM elements using jQuery selector
 * will not allow pointer events on mouse, and will grey out element (50% opacity)
 */
function setElementsEnabled(selector, enabled= true) {
    var elementCss = {
        'pointer-events': enabled ? 'auto' : 'none',
        'opacity': enabled ? '1.0' : '0.5'
    };
    var parentCss = {
        'cursor': enabled ? 'auto' : 'not-allowed'
    };
    selector.css(elementCss).parent().css(parentCss);
    selector.attr('disabled', enabled ? false : 'disabled')
}

// show/hide overlay div & buttons blocking processed matrix file uploads
function setExpressionOverlay(renderOverlay) {
  const overlay = $('#block-processed-upload')
  const content = $('#block-processed-upload-content')
  if (renderOverlay) {
    overlay.addClass('overlay-upload')
    content.removeClass('hide-processed-disclaimer').addClass('show-processed-disclaimer')
  } else {
    overlay.removeClass('overlay-upload')
    content.removeClass('show-processed-disclaimer').addClass('hide-processed-disclaimer')
  }
}

// update all raw counts association dropdowns with new options
function updateRawCountsAssnSelect(parentForm, currentValues, isRequired) {
  const rawAssnTarget = $(`${parentForm} .raw_associations_select`)[0]
  const pairedHiddenField = $(`${parentForm} .raw_counts_associations`)[0]
  const matrixOpts = window.SCP.currentStudyFiles.filter(sf => sf?.expression_file_info?.is_raw_counts)
    .map(sf => ({ label: sf.upload_file_name, value: sf['_id']['$oid'] }))
  const parentFormEl = $(rawAssnTarget).closest('.expression-file-info-fields')[0]
  window.SCP.renderComponent(rawAssnTarget, 'RawAssociationSelect', {
    parentForm: parentFormEl,
    initialValue: currentValues,
    hiddenField: pairedHiddenField,
    opts: matrixOpts,
    isRequired: isRequired
  })
}

/** store a list of components to be rendered once our Vite/React JS loads */
window.SCP.componentsToRender = []
/** Adds somethign to the list of stuff to render once all JS loads.  target can be either an
 * id string or a dom node.
 */
window.SCP.renderComponent = function(target, componentName, props) {
  window.SCP.componentsToRender.push({target: target, componentName: componentName, props: props})
}

window.SCP.eventsToLog = []
/** store any log calls that are made before the JS renders */
window.SCP.log = function(name, props) {
  window.SCP.eventsToLog.push({name: name, props: props})
}
// needed for morpheus import
window.global = {}

