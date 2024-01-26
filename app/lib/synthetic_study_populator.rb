# class to populate synthetic studies from files.
# See db/seed/synthetic_studies for examples of the file formats
#
# to use this on the staging server, you must be logged into the console as the app user
# otherwise files will not be uploaded
# sudo -E -u app -H bin/rails c -e staging
#

class SyntheticStudyPopulator
  DEFAULT_SYNTHETIC_STUDY_PATH = Rails.root.join('db', 'seed', 'synthetic_studies')
  DEFAULT_EXAMPLE_STUDY_PATH = Rails.root.join('db', 'seed', 'example_studies')
  # populates all studies defined in db/seed/synthetic_studies
  def self.populate_all(user: User.first)
    study_names = Dir.glob(DEFAULT_SYNTHETIC_STUDY_PATH.join('*')).select { |f| File.directory? f }
    study_names.each do |study_name|
      populate(study_name, user:)
    end
  end

  # populates the synthetic study specified in the given folder (e.g. ./db/seed/synthetic_studies/blood)
  # destroys any existing studies and workspace data corresponding to that study
  def self.populate(study_folder, user: User.first, detached: false, update_files: false)
    study_path = study_folder
    if study_folder.exclude?('/')
      study_path = DEFAULT_SYNTHETIC_STUDY_PATH.join(study_folder).to_s
      unless File.directory?(study_path)
        study_path = DEFAULT_EXAMPLE_STUDY_PATH.join(study_folder).to_s
      end
      unless File.directory?(study_path)
        raise "No directory found for #{study_folder}"
      end
    end
    study_info_file = File.read(study_path + '/study_info.json')
    study_config = JSON.parse(study_info_file)

    # copy the files to a temp directory, since CarrierWave will delete them after upload
    temp_file_dir = "/tmp/synthetic_studies/#{study_folder}"
    FileUtils.mkdir_p(temp_file_dir)
    FileUtils.cp_r("#{study_path}/.", temp_file_dir)

    puts("Populating study from #{temp_file_dir}")
    study = create_study(study_config, user, detached, update_files)
    add_files(study, study_config, temp_file_dir, user)
    study
  end

  # find all matching instances of synthetic studies
  def self.collect_synthetic_studies
    study_names = []
    synthetic_base_path = DEFAULT_SYNTHETIC_STUDY_PATH
    study_dirs = Dir.glob(synthetic_base_path.join('*')).select { |f| File.directory? f }
    study_dirs.each do |study_dir|
      synthetic_study_folder = synthetic_base_path.join(study_dir).to_s
      study_info_file = File.read(synthetic_study_folder + '/study_info.json')
      study_config = JSON.parse(study_info_file)
      study_names << study_config.dig('study', 'name')
    end
    Study.where(:name.in => study_names)
  end

  def self.create_study(study_config, user, detached, update)
    existing_study = Study.find_by(name: study_config['study']['name'])
    if existing_study
      if update
        return existing_study
      end

      puts("Destroying Study #{existing_study.name}, id #{existing_study.id}")
      if !existing_study.detached
        existing_study.destroy_and_remove_workspace
      else
        existing_study.destroy
      end
    end

    study = Study.new(study_config['study'])
    study.detached = detached
    study.study_detail = StudyDetail.new(full_description: study_config['study']['description'])
    study.user ||= user
    unless study.detached
      study.firecloud_project ||= ENV['PORTAL_NAMESPACE']
    end
    puts("Saving Study #{study.name}")
    study.save!
    study
  end

  def self.add_files(study, study_config, study_folder, user)
    file_infos = study_config['files']
    file_infos.each do |finfo|
      local_file = nil
      begin
        study_file_params = {
          file_type: finfo['type'],
          name: finfo['name'] || 'filename',
          use_metadata_convention: finfo['use_metadata_convention'] ? true : false,
          status: study.detached ? 'new' : 'uploading',
          study:
        }
        if finfo['bucket_url'] && !study.detached
          puts 'moving file from remote bucket into workspace -- you must be signed into gcloud CLI for this to work'
          puts 'getting file info from bucket'
          bucket_file_info = `gcloud storage objects describe #{finfo['bucket_url']}`
          bucket_file_size = bucket_file_info.match(/size:\s*([0-9]*)/)[1]
          puts "File listed as #{bucket_file_size} bytes, beginning copy"
          gcloud_command = "gcloud storage cp #{finfo['bucket_url']} #{study.gs_url}"
          puts gcloud_command
          exit_status = system(gcloud_command)
          unless exit_status
            raise 'Copy file failed -- stopping study population'
          end

          study_file_params[:status] = 'uploaded'
          study_file_params[:upload_file_size] = bucket_file_size
          study_file_params[:remote_location] = finfo['filename']
          study_file_params[:upload_file_name] = finfo['filename']
        else
          local_file = File.open("#{study_folder}/#{finfo['filename']}")
          study_file_params[:upload] = local_file
        end

        study_file_params.merge!(process_genomic_file_params(finfo))
        study_file_params.merge!(process_coordinate_file_params(study, finfo))
        study_file_params.merge!(process_expression_file_params(finfo))
        study_file_params.merge!(process_label_file_params(study, finfo))
        study_file_params.merge!(process_mtx_file_params(study, finfo))
        study_file_params.merge!(process_sequence_file_params(study, finfo))

        study_file = StudyFile.create!(study_file_params)
        # the status has to be 'uploading' when created so the file gets pulled into the workspace
        # after creation, we want it to be uploaded so that, e.g. bundles can create
        study_file.update(status: 'uploaded')
        if !study.detached && study_file.parseable?
          FileParseService.run_parse_job(study_file, study, user)
        else
          # make sure we still create needed bundled for unparsed files (e.g. bam/bai files)
          FileParseService.create_bundle_from_file_options(study_file, study)
          unless study.detached
            study.send_to_firecloud(study_file)
          end
        end
      ensure
        if local_file
          local_file.close
        end
      end
    end
  end

  def self.process_expression_file_params(file_info)
    exp_params = {}
    if file_info['type'] == 'Expression Matrix' || file_info['type'] == 'MM Coordinate Matrix'
      exp_finfo_params = file_info['expression_file_info']
      if exp_finfo_params.present?
        exp_file_info = ExpressionFileInfo.new(
          is_raw_counts: exp_finfo_params['is_raw_counts'] ? true : false,
          units: exp_finfo_params['units'],
          biosample_input_type: exp_finfo_params['biosample_input_type'],
          library_preparation_protocol: exp_finfo_params['library_preparation_protocol'],
          modality: exp_finfo_params['modality']
        )
        exp_params['expression_file_info'] = exp_file_info
      end
    end
    exp_params
  end

  def self.process_label_file_params(study, file_info)
    params = {}
    if file_info['type'] == 'Coordinate Labels'
      unless file_info['cluster_file_name']
        throw 'Coordinate label files must specify a cluster_file_name'
      end
      matching_cluster_file = StudyFile.find_by(name: file_info['cluster_file_name'], study:)
      if matching_cluster_file.nil?
        throw "No cluster file with name #{file_info['cluster_file_name']} to match coordinate labels"
      end
      params[:options] = { 'cluster_file_id' => matching_cluster_file.id.to_s }
    end
    params
  end

  def self.process_mtx_file_params(study, file_info)
    params = {}
    if file_info['type'] == '10X Barcodes File' || file_info['type'] == '10X Genes File'
      matrix_name = file_info['matrix_file_name']
      unless matrix_name
        throw 'Barcodes and Genes files must specify a matrix_file_name'
      end
      matching_mtx_file = StudyFile.find_by(name: matrix_name, study:)
      if matching_mtx_file.nil?
        throw "No MTX file with name #{matrix_name} to match #{file_info['filename']}"
      end
      params[:options] = { 'matrix_id' => matching_mtx_file.id.to_s }
    end
    params
  end

  def self.process_sequence_file_params(study, file_info)
    params = {}
    if file_info['type'] == 'BAM Index'
      unless file_info['bam_file_name']
        throw 'BAM index files must specify a bam_file_name'
      end
      matching_bam_file = StudyFile.find_by(name: file_info['bam_file_name'], study:)
      if matching_bam_file.nil?
        throw "No BAM file with name #{file_info['bam_file_name']} to match bai file"
      end
      params[:options] = { 'bam_id' => matching_bam_file.id.to_s }
    end
    params
  end

  # process coordinate/cluster arguments, return a hash of params suitable for passing to a StudyFile constructor
  def self.process_coordinate_file_params(study, file_info)
    params = {}
    unless file_info['is_spatial'].nil?
      params[:is_spatial] = file_info['is_spatial']
    end
    if file_info['spatial_cluster_associations'].present?
      # look up the ids for the associations
      # note that this requires the associated file to have already been added
      params[:spatial_cluster_associations] = file_info['spatial_cluster_associations'].map do |cluster_file_name|
        StudyFile.find_by!(study:, name: cluster_file_name).id.to_s
      end
    end
    params
  end

  # process species/annotation arguments, return a hash of params suitable for passing to a StudyFile constructor
  def self.process_genomic_file_params(file_info)
    params = {}
    taxon_id = nil
    if file_info['species_scientific_name'].present?
      taxon = Taxon.find_by(scientific_name: file_info['species_scientific_name'])
      if taxon.nil?
        throw "You must populate the species #{file_info['species_scientific_name']} to ingest the file #{file_info['filename']}. Stopping populate"
      end
      params[:taxon_id] = taxon.id
    end
    if file_info['genome_assembly_name'].present?
      if params[:taxon_id].nil?
        throw "You must specify species_scientific_name to specify genome_assembly in #{file_info['filename']}. Stopping populate"
      end
      assembly = GenomeAssembly.find_by(name: file_info['genome_assembly_name'], taxon_id: params[:taxon_id])
      if assembly.nil?
        throw "You must populate the assembly #{file_info['genome_assembly_name']} to ingest the file #{file_info['filename']}. Stopping populate"
      end
      params[:genome_assembly_id] = assembly.id
    end
    if file_info['genome_annotation_name'].present?
      if params[:genome_assembly_id].nil?
        throw "You must specify genome_annotation_name to specify genome_annotation in #{file_info['filename']}. Stopping populate"
      end
      annotation = GenomeAnnotation.find_by(name: file_info['genome_annotation_name'],
                                            genome_assembly_id: params[:genome_assembly_id])
      if assembly.nil?
        throw "You must populate the GenomeAnnotation #{file_info['genome_annotation_name']} to ingest the file #{file_info['filename']}. Stopping populate"
      end
      params[:genome_annotation_id] = annotation.id
    end
    params
  end
end
