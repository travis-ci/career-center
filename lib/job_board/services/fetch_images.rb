require 'job_board'
require 'sequel'

module JobBoard
  module Services
    class FetchImages
      def self.run(params: {})
        new(params: params).run
      end

      attr_reader :params, :infra

      def initialize(params: {})
        @params = params
        @infra = params.fetch('infra')
      end

      def run
        image_query = JobBoard::Models::Image.where(infra: infra)
        images = []

        if params.key?('tags')
          image_query = image_query.where(
            'tags @> ?', Sequel.hstore(params.fetch('tags'))
          )
        end

        limit = params.fetch('limit')
        image_query.reverse_order(:created_at).limit(limit).each do |image|
          images << image
        end

        if images.empty?
          default_image = JobBoard::Models::Image.where(
            infra: infra, is_default: true
          ).first
          images << default_image if default_image
        end

        images
      end
    end
  end
end
