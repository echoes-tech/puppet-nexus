#!/usr/bin/env ruby

require 'optparse'
require 'net/http'

module Nexus

  class Parser

    def self.parse(options)
      abort('No output file provided') unless options[:output]
      parse_gav options
      parse_repository options
    end

    def self.parse_gav(options)
      abort('GAV is required') unless options[:gav]
      sections = options[:gav].split(':')
      abort('GAV is malformed') unless sections.count == 3
      options[:group]    = sections[0]
      options[:artifact] = sections[1]
      options[:version]  = sections[2]
    end

    def self.parse_repository(options)
      return if options[:repository]
      if options[:version] =~ /SNAPSHOT/
        options[:repository] = 'snapshots'
        options[:version] = 'LATEST' if options[:version] == 'LATEST-SNAPSHOT'
      else
        options[:repository] = 'releases'
      end
    end
  end

  class Client

    def initialize(options)
      @rest_path     = '/service/local'
      @content_path  = '/artifact/maven/content'
      @redirect_path = '/artifact/maven/redirect'
      @options = options
      @debug = options[:verbose]
    end

    def download_artifact
      http_call construct_url
      puts 'File download complete' if @debug
    end

    def http_call(url)
      uri = URI.parse url
      request = Net::HTTP::Get.new(uri)
      add_auth request

      puts "Starting download from: #{uri}" if @debug
      response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
        http.read_timeout = 500
        http.request request do |response|
          open @options[:output], 'w' do |io|
            response.read_body do |chunk|
              io.write chunk
            end
          end
        end
      }
      case response
        when Net::HTTPSuccess then
          response
        when Net::HTTPRedirection then
          puts 'Redirect:' if @debug
          http_call response['location']
        else
          abort("File download failed: #{response.code}")
      end
    end

    def add_auth(request)
      if @options[:username] && @options[:password]
        puts "Authenticating as #{@options[:username]}"
        request.basic_auth @options[:username], @options[:password]
      end
    end

    def construct_url
      params = {
          g: @options[:group],
          a: @options[:artifact],
          v: @options[:version],
          r: @options[:repository],
          p: @options[:extension],
          c: @options[:classifier],
      }
      param_string = params.reject { |k,v| v.nil? }.collect { |k,v| "#{k}=#{v}" }.join('&')
      "#{@options[:base_url]}#{@rest_path}#{@redirect_path}?#{param_string}"
    end
  end
end

options = {
    extension: 'jar',
    verbose: false,
}

OptionParser.new do |opts|
  opts.banner = 'This script will fetch an artifact from a Nexus server using the Nexus REST service'
  opts.on('-n', '--nexus URL', 'Nexus base url')             { |n| options[:base_url] = n }
  opts.on('-u', '--username USER', 'Nexus username')         { |u| options[:username] = u }
  opts.on('-p', '--password PASS', 'Nexus password')         { |p| options[:password] = p }
  opts.on('-m', '--netrc', 'Use .netrc')                     { |m| options[:netrc] = m }
  opts.on('-a', '--gav GAV', 'group:artifact:version')       { |a| options[:gav] = a }
  opts.on('-r', '--repository REPO', 'Repository')           { |r| options[:repository] = r }
  opts.on('-e', '--extension EXT', 'Artifact Extension')     { |e| options[:extension] = e }
  opts.on('-c', '--classifier CLASS', 'Artifact Classifier') { |c| options[:classifier] = c }
  opts.on('-o', '--output FILE', 'Output file')              { |o| options[:output] = o }
  opts.on('-z', '--newer', 'Newer')                          { |z| options[:z] = z }
  opts.on('-v', '--verbose', 'Verbose')                      { |v| options[:verbose] = v }
end.parse!

# -z = if nexus has newer version of artifact, remove Output File and exit
# aka SNAPSHOT_CHECK=1

Nexus::Parser.parse options

client = Nexus::Client.new(options)
client.download_artifact

# if [[ "$SNAPSHOT_CHECK" != "" ]]
# then
#   # remove $OUTPUT if nexus has newer version
#   if [[ -f $OUTPUT ]] && [[ "$(curl -s ${REDIRECT_URL} ${AUTHENTICATION} -I --location-trusted -z $OUTPUT -o /dev/null -w '%{http_code}' )" == "200" ]]
#   then
#     echo "Nexus has newer version of $GROUP_ID:$ARTIFACT_ID:$VERSION"
#     rm $OUTPUT
#   fi
#   exit 0
# fi