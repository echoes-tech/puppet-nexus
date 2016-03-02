#!/usr/bin/env ruby

require 'optparse'
require 'net/http'

module Nexus

  class Parser
    def self.parse(options)
      abort('No output file provided') unless options[:output]
      parse_gav options
      parse_repository options
      options
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
      @options = Nexus::Parser.parse options
    end

    def download_artifact
      url  = create_url
      args = create_arg_string

      log "Starting download from: #{url}"
      output = `curl #{args} "#{url}" -o #{@options[:output]} -w '%{http_code}'`

      abort("File download failed: #{output}") if $?.exitstatus != 0
      log 'File download complete'
    end

    def create_arg_string
      args = [ '-R', '--fail', '--location-trusted' ]
      if @options[:netrc]
        log 'Authenticating using netrc'
        args.push '-n'
      elsif @options[:username] && @options[:password]
        log "Authenticating as #{@options[:username]}"
        args.push "-u #{@options[:username]}:#{@options[:password]}"
      end
      args.push @options[:verbose] ? '-v' : '-sS'
      args.join(' ')
    end

    def create_url
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

    def log(message)
      puts message if @options[:verbose]
    end
  end
end

options = { extension: 'jar', verbose: false, }
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