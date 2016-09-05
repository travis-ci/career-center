# frozen_string_literal: true
require 'json'

require_relative 'auth'
require_relative 'config'
require_relative 'models'
require_relative 'image_searcher'

require 'rack/auth/basic'
require 'rack/deflater'
require 'sequel'
require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/param'

module JobBoard
  class App < Sinatra::Base
    helpers Sinatra::Param

    use JobBoard::Auth
    use Rack::Deflater

    before { content_type :json }

    helpers do
      def guest?
        (env['REMOTE_USER'] || 'notset') == 'guest'
      end

      def set_images_mutation_params
        param :infra, String, blank: true, required: true
        param :is_default, Boolean
        param :is_active, Boolean
        param :tags, Hash, default: {}
        param :name, String, blank: true, required: true,
                             format: images_name_format
      end

      def images_name_format
        @images_name_format ||= /#{JobBoard.config.images_name_format}/
      end
    end

    get '/images' do
      param :infra, String, blank: true, required: true
      param :name, String, blank: true
      param :tags, Hash, default: {}
      param :limit, Integer, default: 0
      param :is_default, Boolean, default: false
      param :is_active, Boolean, default: true

      images = JobBoard::Services::FetchImages.run(params: params)
      data = images.map(&:to_hash)

      data = images_fields(data, fields) unless fields.empty?

      status 200
      json data: data,
           meta: { limit: params.fetch('limit') }
    end

    # This is a POST-ish version of `GET /images` that accepts a body of
    # line-delimited queries, returning with the first query with results
    post '/images/search' do
      images, matching_query, limit = image_searcher.search(request.body.read)
      data = images.map(&:to_hash)

      fields = (matching_query['fields[images]'] || '').split(',').map do |key|
        key.strip.to_sym
      end

      data = images_fields(data, fields) unless fields.empty?

      status 200
      json data: data,
           meta: { limit: limit, matching_query: matching_query }
    end

    post '/images' do
      halt 403 if guest?

      set_images_mutation_params

      params['is_default'] = false unless params.key?('is_default')
      params['is_active'] = false unless params.key?('is_active')

      image = JobBoard::Services::CreateImage.run(params: params)

      status 201
      json data: [image.to_hash]
    end

    # This looks like a general-purpose PATCH updater, but in reality it is only
    # used for updating `is_active`... for now.
    patch '/images' do
      halt 403 if guest?

      param :infra, String, blank: true, required: true
      param :name, String, blank: true, required: true
      param :is_active, Boolean, blank: true, required: true

      images = JobBoard::Services::ActivateImages.run(params: params)
      data = images.map(&:to_hash)

      data = images_fields(data, fields) unless fields.empty?

      status 200
      json data: data
    end

    put '/images' do
      halt 403 if guest?

      set_images_mutation_params

      params['is_default'] = false unless params.key?('is_default')
      params['is_active'] = false unless params.key?('is_active')

      image = JobBoard::Services::UpdateImage.run(params: params)
      halt 404 if image.nil?

      status 200
      json data: [image.to_hash]
    end

    delete '/images' do
      halt 403 if guest?

      set_images_mutation_params

      n_destroyed = JobBoard::Services::DeleteImages.run(params: params)
      halt 404 if n_destroyed.zero?

      [204, {}, '']
    end

    private

    def fields
      ((params['fields'] || {})['images'] || '').split(',').map do |key|
        key.strip.to_sym
      end
    end

    def image_searcher
      @image_searcher ||= JobBoard::ImageSearcher.new
    end

    def images_fields(images, fields)
      images.map do |image|
        image.delete_if { |k, _| !fields.include?(k) }
      end
    end
  end
end
