#!/usr/bin/env ruby
# encoding: UTF-8

# "Can I Call It...?", a tool to help name new open source projects

require 'rubygems'
require 'bundler/setup'
require 'unicorn'
require 'sinatra'
require 'net/http'
require 'json'
require 'nokogiri'
require 'xmlrpc/client'

GITHUB_API_PATH = 'http://api.github.com/legacy/repos/search/'
GITHUB_MIN_FORKS = 10 # Min. number of forks to qualify as a meaningful Github project
RUBYGEMS_API_PATH = 'https://rubygems.org/api/v1/search.json?query='
PYPI_API_PATH = 'http://pypi.python.org/pypi'
SOURCEFORGE_API_PATH = 'http://sourceforge.net/api/project/name/'
MAVEN_API_PATH = 'http://search.maven.org/solrsearch/select?rows=20&wt=json&q=a:'

# Serve page
get '/' do
  if params.has_key?("search")
    term = params['search']
    matches = []

    # Populate Matches array
    findSourceForgeProjects(term, matches)
    findGithubProjects(term, matches)
    findRubyGems(term, matches)
    findPyPIPackages(term, matches)
    findMavenPackages(term, matches)

    # Mangle the Matches arrays as necessary
    matches.uniq!
    exactMatches = matches.select{ |match| (match[:exact] == true)}
    matches = matches - exactMatches

    # Generate results output
    erb :results, :locals => {:term => term, :result => printHTML(term, exactMatches, matches)}
  else
    # Generate main page output
    erb :index
  end
end

# 404
not_found do
  status 404
  '<h1>Page not found</h1>'
end

# Find Projects on SourceForge
def findSourceForgeProjects(term, matches)
  begin
    uri = URI.parse("#{SOURCEFORGE_API_PATH}#{term}/json")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    if rhash.has_key?('Project')
      maintainers = ''
      rhash['Project']['maintainers'].each do |maintainer|
        maintainers << "#{maintainer['name']}, "
      end
      maintainers = maintainers[0..-3]
      matches << {:name => rhash['Project']['name'], :by => maintainers, :url => rhash['Project']['summary-page'], :description => rhash['Project']['description'], :source => 'SourceForge', :exact => true}
    end
  rescue
  end
end

# Find Projects on Github
def findGithubProjects(term, matches)
  begin
    uri = URI.parse("#{GITHUB_API_PATH}#{term}?sort=forks")
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash['repositories'].each do |repo|
      if repo['forks'] > GITHUB_MIN_FORKS
        matches << {:name => repo['name'], :by => repo['username'], :url => repo['url'], :description => repo['description'], :source => 'GitHub', :exact => (term == repo['name'])}
      end
    end
  rescue
  end
end

# Find RubyGems
def findRubyGems(term, matches)
  begin
    uri = URI.parse("#{RUBYGEMS_API_PATH}#{term}")
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash.each do |rubygem|
      matches << {:name => rubygem['name'], :by => rubygem['authors'], :url => rubygem['project_uri'], :description => rubygem['info'], :source => 'Ruby Gems', :exact => (term == rubygem['name'])}
    end
  rescue
  end
end

# Find PyPI Packages
def findPyPIPackages(term, matches)
  begin
    client = XMLRPC::Client.new2("#{PYPI_API_PATH}")
    client.http_header_extra = {"Content-Type" => "text/xml"}
    result = client.call('search', {'name' => term})
    result.each do |package|
      matches << {:name => package['name'], :by => '', :url => "https://pypi.python.org/pypi/#{package['name']}/", :description => package['summary'], :source => 'PyPI', :exact => (term == package['name'])}
    end
  rescue
  end
end

# Find Packages on Maven
def findMavenPackages(term, matches)
  begin
    uri = URI.parse("#{MAVEN_API_PATH}%22#{term}%22")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash['response']['docs'].each do |package|
      matches << {:name => package['a'], :by => '', :url => "http://search.maven.org/#search%7Cga%7C1%7Ca%3A%22#{package['a']}%22", :description => '', :source => 'Maven', :exact => (term == package['a'])}
    end
  rescue
  end
end

# Print the HTML for the results. Quick and dirty.
def printHTML(term, exactMatches, matches)
  html = ''

  if matches.length == 0
    html << "<h1>Yes.</h1><h2>You can call your project '#{term}', it's unique!</h2>"
  elsif exactMatches.length == 0
    html << "<h1>Maybe.</h1><h2>We didn't find any exact matches for '#{term}', but we did find #{matches.length} similarly-named project(s).</h2>"
    html << '<table border=1 cellspacing=0 cellpadding=3><tr><th>Project</th><th>By...</th><th>Found on...</th><th>Description</th></tr>'
    matches.each do |match|
      html << "<tr><td><a href='#{match[:url]}'>#{match[:name]}</a></td><td>#{match[:by]}</td><td>#{match[:source]}</td><td>#{match[:description]}</td></tr>"
    end
    html << '</table>'
  else
    html << "<h1>No.</h1><h2>We found #{exactMatches.length} project(s) called '#{term}'.</h2>"
    html << '<table border=1 cellspacing=0 cellpadding=3><tr><th>Project</th><th>By...</th><th>Found on...</th><th>Description</th></tr>'
    exactMatches.each do |match|
      html << "<tr><td><a href='#{match[:url]}'>#{match[:name]}</a></td><td>#{match[:by]}</td><td>#{match[:source]}</td><td>#{match[:description]}</td></tr>"
    end
    html << '</table>'
    html << "<h2>We also found #{matches.length} project(s) with similar names.</h2>"
    html << '<table border=1 cellspacing=0 cellpadding=3><tr><th>Project</th><th>By...</th><th>Found on...</th><th>Description</th></tr>'
    matches.each do |match|
      html << "<tr><td><a href='#{match[:url]}'>#{match[:name]}</a></td><td>#{match[:by]}</td><td>#{match[:source]}</td><td>#{match[:description]}</td></tr>"
    end
    html << '</table>'
  end

end
