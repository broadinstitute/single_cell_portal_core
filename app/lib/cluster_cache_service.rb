##
# For pre-caching cluster visualization responses to speed up loading default responses
##
class ClusterCacheService
  # return the output from a url_helper, such as api_v1_study_cluster_path(study, cluster_name)
  #
  # * *params*
  #   - +route_name+ (String, Symbol) => name of route from routes.rb (as: declaration)
  #   - +params+ (*Array) => request parameters, supports path-level and query string (as Hash), passed with splat (*)
  #
  # * *returns*
  #   - (String) => Request path with all parameters interpolated in
  def self.format_request_path(route_name, *params)
    Rails.application.routes.url_helpers.send(route_name, *params)
  end

  # pre-cache all default clusters/annotations for every study
  # use accession list to prevent long-lived query cursors from timing out in Delayed::Job
  def self.cache_all_defaults
    accessions = Study.pluck(:accession)
    accessions.each do |accession|
      begin
        study = Study.find_by(accession: accession)
        cache_study_defaults(study)
      rescue Mongo::Error::OperationFailure => e
        ErrorTracker.report_exception(e, nil,
                                      { study_accession: accession, operation: :cache_study_defaults })
        Rails.logger.error "Error caching study defaults for #{accession}: #{e.message}"
        next
      end
    end
  end

  # pre-cache the default cluster & annotation for a given study
  #
  # * *params*
  #   - +study+ (Study) => study to cache defaults for
  #
  # * *yields*
  #   - (JSON) => ActionDispatch::Cache entry of JSON viz data
  def self.cache_study_defaults(study)
    Rails.logger.info "Checking defaults on #{study.accession} for pre-caching"
    unless study.can_visualize_clusters?
      Rails.logger.info "#{study.accession} cannot visualize clusters, skipping"
      return nil
    end
    begin
      cluster = study.default_cluster
      annotation = study.default_annotation
      if cluster && annotation
        annotation_name, annotation_type, annotation_scope = annotation.split('--')
        # necessary for legacy cluster names that could contain slashes and other non URL-safe characters
        sanitized_cluster_name = cluster.name.include?('/') ? CGI.escape(cluster.name) : cluster.name
        full_params = {
          annotation_name: annotation_name, annotation_scope: annotation_scope, annotation_type: annotation_type,
          subsample: 'all', cluster_name: sanitized_cluster_name, fields: 'coordinates,cells,annotation'
        }
        default_params = {
          cluster_name: '_default',
          fields: 'coordinates,cells,annotation'
        }
        [default_params, full_params].each do |url_params|
          path = format_request_path(:api_v1_study_cluster_path, study.accession, url_params[:cluster_name])
          cache_path = RequestUtils.get_cache_path(path, url_params.with_indifferent_access)
          viz_data = Api::V1::Visualization::ClustersController.get_cluster_viz_data(study, cluster, url_params)
          Rails.logger.info "Pre-caching viz data for #{cache_path}"
          Rails.cache.write(cache_path, viz_data.to_json)
        end
      else
        Rails.logger.info "No defaults present for #{study.accession}; skip caching study defaults"
      end
    rescue => e
      ErrorTracker.report_exception(e, nil, study)
      Rails.logger.error "Error in caching defaults for #{study.accession}: (#{e.class.name}) #{e.message}"
    end
  end

  # set the default annotation for a study to the most relevant annotation available,
  # such as cell_type__ontology_label or seurat_clusters
  def self.configure_default_annotation(study)
    return false if default_annotation_configured?(study)

    best_available = best_available_annotation(study)
    return false if best_available.nil?

    # use default_options[:annotation] as default_annotation has fallback logic and we want the 'configured' value
    existing_default = study.default_options[:annotation]
    return false if best_available == existing_default

    study.default_options[:annotation] = best_available
    Rails.logger.info "Changing default annotation in #{study.accession} from " \
                        "#{existing_default.presence || 'unassigned'} to #{best_available}"
    study.save(validate: false) # prevent validation errors for older studies
    log_props = {
      studyAccession: study.accession,
      default_annotation: best_available,
      previous_annotation: existing_default
    }
    MetricsService.log('study-default-annotation', log_props, study.user)
  end

  # find the most relevant annotation to display as the default
  # will prioritize convention-based cell types, then other 'cell type'-like annotations,
  # followed by clustering algorithms and anything label/categorical in nature
  def self.best_available_annotation(study)
    annotations = DifferentialExpressionService.find_eligible_annotations(study)
    return nil if annotations.empty?

    ontology = annotations.detect { |a| a[:annotation_name] == 'cell_type__ontology_label' }
    author_cell_type = annotations.detect { |a| a[:annotation_name] =~ /author.*cell.*type/i }
    clustering = annotations.detect { |a| a[:annotation_name] =~ DifferentialExpressionService::CLUSTERING_MATCHER }
    category = annotations.detect { |a| a[:annotation_name] =~ DifferentialExpressionService::CATEGORY_MATCHER }
    best_avail = ontology || author_cell_type || clustering || category

    best_avail.present? ? [best_avail[:annotation_name], 'group', best_avail[:annotation_scope]].join('--') : nil
  end

  # helper to determine if a user set the default annotation manually by checking HistoryTracker for events
  def self.default_annotation_configured?(study)
    study.history_tracks.detect do |track|
      track.original.dig('default_options', 'annotation').present? &&
        track.original.dig('default_options', 'annotation') != '' &&
        track.modified.dig('default_options', 'annotation') != track.original.dig('default_options', 'annotation')
    end.present?
  end
end
