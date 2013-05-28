# encoding: UTF-8

require 'rack/google-analytics'
use Rack::GoogleAnalytics, :tracker => 'UA-40732019-9'

require './canicallit'

run Sinatra::Application
