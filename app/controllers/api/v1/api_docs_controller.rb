module Api
  module V1
    class ApiDocsController < ActionController::Base
      include Swagger::Blocks
      include Concerns::CspHeaderBypass

      respond_to :json

      swagger_root do
        key :swagger, '2.0'
        info do
          key :version, 'v1'
          key :title, 'Single Cell Portal REST API'
          key :description, 'REST API Documentation for the Single Cell Portal'
          license do
            key :name, 'BSD-3-Clause'
            key :url, 'http://opensource.org/licenses/BSD-3-Clause'
          end
        end
        tag do
          key :name, 'Site'
          key :description, 'Browse public/shared Studies, and configure/submit Analyses'
        end
        tag do
          key :name, 'Search'
          key :description, 'Keyword and Faceted search operations'
        end
        tag do
          key :name, 'Status'
          key :description, 'Status operations'
        end
        tag do
          key :name, 'Studies'
          key :description, 'Study operations'
        end
        tag do
          key :name, 'StudyFiles'
          key :description, 'StudyFile operations'
        end
        tag do
          key :name, 'StudyFileBundles'
          key :description, 'StudyFileBundle operations'
        end
        tag do
          key :name, 'StudyShares'
          key :description, 'StudyShare operations'
        end
        tag do
          key :name, 'DirectoryListings'
          key :description, 'DirectoryListing operations'
        end
        tag do
          key :name, 'ExternalResources'
          key :description, 'Study publication/data link operations'
        end
        tag do
          key :name, 'MetadataSchemas'
          key :description, 'Metadata Convention schema definitions'
        end
        tag do
          key :name, 'Schemas'
          key :description, 'Descriptions of SCP model schemas'
        end
        tag do
          key :name, 'Taxons'
          key :description, 'List of available species, genome assemblies & annotations'
        end
        key :host, "#{ENV['HOSTNAME']}#{ENV['NOT_DOCKERIZED'] ? ':3000' : nil}"
        key :basePath, '/single_cell/api/v1'
        key :consumes, ['application/json']
        key :produces, ['application/json']
        security_definition :google_oauth2 do
          key :type, :oauth2
          key :authorizationUrl, "https://accounts.google.com/o/oauth2/auth"
          key :flow, :implicit
          scopes do
            key 'https://www.googleapis.com/auth/userinfo.email', 'email authorization'
            key 'https://www.googleapis.com/auth/userinfo.profile', 'profile authorization'
          end
        end
        security do
          key :google_oauth2, %w(https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile)
        end
      end

      SWAGGERED_CLASSES = [
          self,
          Study,
          StudyFile,
          DirectoryListing,
          SearchFacet,
          StudyShare,
          StudyFileBundle,
          Taxon,
          AnalysisConfiguration,
          ExternalResource,
          Api::V1::StudiesController,
          Api::V1::StudyFilesController,
          Api::V1::StudyFileBundlesController,
          Api::V1::StudySharesController,
          Api::V1::DirectoryListingsController,
          Api::V1::ExternalResourcesController,
          Api::V1::SchemasController,
          Api::V1::MetadataSchemasController,
          Api::V1::TaxonsController,
          Api::V1::StatusController,
          Api::V1::SiteController,
          Api::V1::SearchController
      ].freeze

      def index
        render json: Swagger::Blocks.build_root_json(SWAGGERED_CLASSES)
      end
    end
  end
end
