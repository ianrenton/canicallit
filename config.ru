# encoding: UTF-8
require './canicallit'
require 'rack/google-analytics'

use Rack::GoogleAnalytics, :tracker => 'UA-40732019-9'

run Sinatra::Application
