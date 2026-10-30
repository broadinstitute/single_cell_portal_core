require 'test_helper'

class DownloadRequestTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Download Request Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    5.times do |i|
      FactoryBot.create(
        :study_file, name: "cluster_#{i}.txt", file_type: 'Cluster', study: @study
      )
    end
  end

  test 'should transform azul_file hashes to JSON and back' do

    azul_hash = {
        'Fake.HCA.Study.1' => [
          {
            'source' => 'hca',
            'count' => 1,
            'upload_file_size' => 10.megabytes,
            'file_format' => 'loom',
            'file_type' => 'analysis_file',
            'accession' => 'FakeHCAStudy1',
            'project_id' => 'hca_project_id'
          }
        ],
        'Fake.HcaS.tu.d.y.2' => []
      }

    download_req = DownloadRequest.create!(
      azul_files: azul_hash
    )

    download_req.save!

    assert_equal azul_hash , download_req.azul_files_as_hash
    assert_equal ActiveSupport::JSON.encode(azul_hash), download_req.azul_files.gsub(' ', '')

    download_req.update!(azul_files: nil)
    assert_nil download_req.azul_files
    assert_equal({}, download_req.azul_files_as_hash)

  end

  test 'should load study files' do
    download = DownloadRequest.create(
      file_ids: [@study.study_files.pluck(:id)]
    )

    assert_equal @study.study_files, download.study_files
  end
end

