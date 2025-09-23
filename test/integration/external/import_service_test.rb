require 'test_helper'

class ImportServiceTest < ActiveSupport::TestCase
  before(:all) do
    @nemo_attributes = {
      file_id: 'nemo:alc-t6a5pxv',
      project_id: 'nemo:grn-gyy3k8j',
      study_id: 'nemo:col-f3yvj88'
    }
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should call API client method' do
    client = NemoClient.new
    nemo_file = ImportService.call_api_client(client, :file, @nemo_attributes[:file_id])
    assert_equal 'BI006_marm028_Munchkin_M1_rxn1.4.bam.bai', nemo_file['file_name']
    assert_equal 'bam', nemo_file['file_format']
    assert_raises ArgumentError do
      ImportService.call_api_client(FireCloudClient.new, :api_available?)
    end
  end

  test 'should call import from external service' do
    mock = Minitest::Mock.new
    mock.expect :valid?, true
    mock.expect :import_from_service, [Study.new, StudyFile.new]
    ImportServiceConfig::Nemo.stub :new, mock do
      ImportService.import_from(ImportServiceConfig::Nemo, **@nemo_attributes)
      mock.verify
    end
  end

  test 'should instantiate storage' do
    assert ImportService.storage.present?
    assert_equal ENV['GOOGLE_CLOUD_PROJECT'], ImportService.storage.project
  end

  test 'should get public bucket' do
    bucket_id = 'broad-singlecellportal-public'
    bucket = ImportService.load_public_bucket bucket_id
    assert bucket.present?
    bucket.is_a?(Google::Cloud::Storage::Bucket)
    assert bucket.lazy? # skip_lookup: true
  end

  test 'should get public file from bucket' do
    bucket_id = 'broad-singlecellportal-public'
    filepath = 'test/studies/SCP1671/MIT_milk_study_metadata.csv.gz'
    file = ImportService.load_public_gcp_file(bucket_id, filepath)
    assert file.present?
    assert file.is_a?(Google::Cloud::Storage::File)
    assert_equal filepath, file.name
    assert_equal bucket_id, file.bucket
    assert file.lazy? # skip_lookup: true
  end

  test 'should parse gs URL' do
    url = 'gs://bucket-name/path/to/dataset.h5ad'
    bucket, path = ImportService.parse_gs_url(url)
    assert_equal 'bucket-name', bucket
    assert_equal 'path/to/dataset.h5ad', path
  end

  # this is a true integration test that will create a GCP bucket, then pull file from remote location and push
  test 'should copy file to bucket' do
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    study = FactoryBot.create(:study,
                              name_prefix: 'ImportService test',
                              public: false,
                              user: user,
                              test_array: @@studies_to_clean)
    bucket = 'broad-singlecellportal-public'
    filepath = 'test/studies/SCP1671/MIT_milk_study_metadata.csv.gz'
    filename = 'MIT_milk_study_metadata.csv.gz'
    workspace_bucket = ImportService.storage.bucket study.bucket_id
    gs_url = ['gs:/', bucket, filepath].join('/')
    public_url = ['https://storage.googleapis.com', bucket, filepath].join('/')
    # test copy via https
    https_copy = ImportService.copy_file_to_bucket(public_url, study.bucket_id, filename)
    assert https_copy.present?
    assert https_copy.is_a?(Google::Cloud::Storage::File)
    # delete file
    https_copy.delete
    assert_nil workspace_bucket.file filepath
    # test copy via gs
    gs_copy = ImportService.copy_file_to_bucket(gs_url, study.bucket_id, filename)
    assert gs_copy.present?
    assert gs_copy.is_a?(Google::Cloud::Storage::File)
  end
end
