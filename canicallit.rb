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

GITHUB_API_PATH = 'http://api.github.com/legacy/repos/search/~?sort=stars'
GITHUB_MIN_WATCHERS = 5 # Min. number of watchers to qualify as a meaningful Github project
RUBYGEMS_API_PATH = 'https://rubygems.org/api/v1/search.json?query=~'
PYPI_API_PATH = 'http://pypi.python.org/pypi'
SOURCEFORGE_API_PATH = 'http://sourceforge.net/api/project/name/~/json'
MAVEN_API_PATH = 'http://search.maven.org/solrsearch/select?rows=20&wt=json&q=a:%22~%22'
DEBIAN_PACKAGES_PATH = 'http://packages.debian.org/search?keywords=~&searchon=names&suite=all&section=all'
DEBIAN_BASE_URL = 'http://packages.debian.org'
FEDORA_PACKAGEDB_API_PATH = 'https://admin.fedoraproject.org/pkgdb/acls/name/~?tg_format=json'

# Serve home page or redirect
get '/' do
  if params.has_key?('search')
    # Redirect to nicer URL
    redirect "/#{params['search']}", 303
  else
    # Generate main page output
    erb :index
  end
end

# Serve result page
get '/:term' do
  term = params['term']
  matches = []
  allServices = ['SourceForge', 'GitHub', 'Ruby Gems', 'PyPI', 'Maven', 'Debian', 'Fedora']
  erroredServices = []
  errors = []

  # Populate Matches array
  findSourceForgeProjects(term, matches, erroredServices)
  findGithubProjects(term, matches, erroredServices)
  findRubyGems(term, matches, erroredServices)
  findPyPIPackages(term, matches, erroredServices)
  findMavenPackages(term, matches, erroredServices)
  findDebianPackages(term, matches, erroredServices)
  findFedoraPackages(term, matches, erroredServices)

  # Mangle the result arrays as necessary
  matches.uniq!
  matches.sort!{ |x,y| x[:name].downcase <=> y[:name].downcase }
  exactMatches = matches.select{ |match| (match[:exact] == true)}
  matches = matches - exactMatches
  okServices = allServices - erroredServices

  # Generate results output using a template
  generateResults(term, exactMatches, matches, okServices, erroredServices)
end

# 404
not_found do
  status 404
  '<h1>Page not found</h1>'
end

# Find Projects on SourceForge
def findSourceForgeProjects(term, matches, erroredServices)
  begin
    uri = URI.parse(SOURCEFORGE_API_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 10
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
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'SourceForge'
  end
end

# Find Projects on Github
def findGithubProjects(term, matches, erroredServices)
  begin
    uri = URI.parse(GITHUB_API_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, 443)
    http.read_timeout = 10
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash['repositories'].each do |repo|
      if repo['watchers'] > GITHUB_MIN_WATCHERS
        matches << {:name => repo['name'], :by => repo['username'], :url => repo['url'], :description => repo['description'], :source => 'GitHub', :exact => (term.downcase == repo['name'].downcase)}
      else
        break
      end
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'GitHub'
  end
end

# Find RubyGems
def findRubyGems(term, matches, erroredServices)
  begin
    uri = URI.parse(RUBYGEMS_API_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, 443)
    http.read_timeout = 10
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash.each do |rubygem|
      matches << {:name => rubygem['name'], :by => rubygem['authors'], :url => rubygem['project_uri'], :description => rubygem['info'], :source => 'Ruby Gems', :exact => (term.downcase == rubygem['name'].downcase)}
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'Ruby Gems'
  end
end

# Find PyPI Packages
def findPyPIPackages(term, matches, erroredServices)
  begin
    client = XMLRPC::Client.new2("#{PYPI_API_PATH}")
    client.http_header_extra = {"Content-Type" => "text/xml"}
    client.timeout = 10
    result = client.call('search', {'name' => term})
    result.each do |package|
      matches << {:name => package['name'], :by => '', :url => "#{PYPI_API_PATH}/#{package['name']}", :description => package['summary'], :source => 'PyPI', :exact => (term.downcase == package['name'].downcase)}
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'PyPI'
  end
end

# Find Packages on Maven
def findMavenPackages(term, matches, erroredServices)
  begin
    uri = URI.parse(MAVEN_API_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 10
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    rhash['response']['docs'].each do |package|
      matches << {:name => package['a'], :by => '', :url => "http://search.maven.org/#search%7Cga%7C1%7Ca%3A%22#{package['a']}%22", :description => '', :source => 'Maven', :exact => (term.downcase == package['a'].downcase)}
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'Maven'
  end
end

# Find Packages on Debian package database
def findDebianPackages(term, matches, erroredServices)
  begin
    uri = URI.parse(DEBIAN_PACKAGES_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 10
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    doc = Nokogiri::HTML(res.body)
    # Search the results div for h3 blocks, these have the package names
    doc.xpath('//div[./@id="psearchres"]/h3').each do |h3|
      name = h3.content.sub(/^Package /, '')
      li = h3.xpath('following-sibling::ul/li').first
      url = DEBIAN_BASE_URL + li.xpath('a/@href').first.value
      description = li.content.lines.to_a[1]

      matches << {:name => name, :url => url, :description => description, :source => 'Debian', :exact => (term.downcase == name.downcase)}
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'Debian'
  end
end

# Find Packages on Fedora PackageDB
def findFedoraPackages(term, matches, erroredServices)
  begin
    uri = URI.parse(FEDORA_PACKAGEDB_API_PATH.sub('~', term))
    http = Net::HTTP.new(uri.host, 443)
    http.read_timeout = 10
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Get.new(uri.request_uri)
    res = http.request(request)
    rhash = JSON.parse(res.body)
    if rhash.has_key?('packageListings') && rhash['packageListings'].length > 0
      package = rhash['packageListings'][0]
      matches << {:name => package['package']['name'], :by => package['owner'], :url => "https://admin.fedoraproject.org/pkgdb/acls/name/#{term}", :description => package['package']['summary'], :source => 'Fedora PackageDB', :exact => true}
    end
  rescue Exception => e  
    puts e.message  
    puts e.backtrace.inspect 
    erroredServices << 'Fedora'
  end
end

# Generate results output using a template
def generateResults(term, exactMatches, matches, okServices, erroredServices)

  if term == 'canicallit'
    heading = 'No.<br/><br/>That would just be rude.'
  elsif (matches.length == 0) && (exactMatches.length == 0)
    heading = 'Yes.'
    summary1 = "You can call your project '#{term}', it's unique!"
  elsif exactMatches.length == 0
    heading = 'Maybe.'
    summary3 = "We didn't find any exact matches for '#{term}', but we did find #{matches.length} similarly-named project(s)."
  else
    heading = 'No.'
    summary2 = "We found #{exactMatches.length} project(s) called '#{term}'."
    if matches.length > 0
      summary3 = "We also found #{matches.length} project(s) with similar names."
    end
  end

  erb :results, :locals => {:term => term, :heading => heading, :summary1 => summary1, :summary2 => summary2, :summary3 => summary3, :exactMatches => exactMatches, :matches => matches, :okServices => okServices, :erroredServices => erroredServices, :githubminwatchers => GITHUB_MIN_WATCHERS}

end
