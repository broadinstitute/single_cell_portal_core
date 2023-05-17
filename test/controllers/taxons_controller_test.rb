require 'integration_test_helper'
require 'test_helper'
require 'includes_helper'

class TaxonsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @random_seed = SecureRandom.uuid
    Taxon.destroy_all
  end

  setup do
    auth_as_user(@user)
    sign_in @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Taxon.destroy_all
  end

  test 'should create new taxon then update and delete' do
    get taxons_path
    assert_response 200, "Did not load taxons path, expected response code of 200 but found #{@response.code}"
    # create taxon
    taxon_params = {
      taxon: {
        common_name: 'Mouse',
        scientific_name: 'Mus Musculus',
        ncbi_taxid: 10090,
        user_id: @user.id.to_s,
        notes: "Test run #{@random_seed}",
        genome_assemblies_attributes: {
          '0' => {
            name: 'GRCm38',
            accession: 'GCA_000001635.2',
            release_date: '2012-01-09'
          }
        }
      }
    }
    post taxons_path, params: taxon_params
    assert_response 302, "Did not successfully create taxon, expected redirect code 302 but found #{@response.code}"
    follow_redirect!
    @taxon = Taxon.first
    assert @taxon.present?, "Taxon did not save: @taxon.present?: #{@taxon.present?}"
    # update taxon
    update_params = {
      taxon: {
        aliases: 'House mouse'
      }
    }
    patch taxon_path(@taxon), params: update_params
    assert_response 302, "Did not successfully update taxon, expected redirect code 302 but found #{@response.code}"
    follow_redirect!
    @taxon = Taxon.first
    assert @taxon.aliases == update_params[:taxon][:aliases],
           "Did not update aliases field, #{update_params[:taxon][:aliases]} != #{@taxon.aliases}"
    # delete taxon
    delete taxon_path(@taxon)
    assert_response 302, "Did not successfully create taxon, expected redirect code 302 but found #{@response.code}"
    follow_redirect!
    assert !Taxon.present?, "Did not delete taxon, current count: #{Taxon.count}"
  end

  test 'should create taxons from upload' do
    get taxons_path
    assert_response 200, 'Did not load taxons path'
    taxon_file = Rack::Test::UploadedFile.new(Rails.root.join('lib', 'assets', 'default_species_assemblies.txt'))
    post upload_species_list_path, params: { upload: taxon_file }
    follow_redirect!
    assert path == taxons_path, "Did not redirect to taxons path after upload, current path is #{path}"
    assert Taxon.count == 11, "Did not create all taxons from file, expected 11 but found #{Taxon.count}"
    assert GenomeAssembly.count == 35,
           "Did not create all assemblies from file, expected 35 but found #{GenomeAssembly.count}"
  end
end

