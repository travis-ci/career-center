#!/usr/bin/env rackup

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'job_board'

$stdout.sync = true if ENV.key?('DYNO')
STDOUT.sync = true if ENV.key?('DYNO')

unless %w(development test).include?(ENV['RACK_ENV'] || 'bogus')
  require 'rack/ssl'
  use Rack::SSL
end

run JobBoard::App
