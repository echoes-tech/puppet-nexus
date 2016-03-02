#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'digest/sha1'

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
      # Explicitly download artifact to a temp file in case of errors
      # According to curl man page, the --fail option is not fail-safe
      temp_file = generate_temp_file_path
      abort('Temp file collision') if File.exist? temp_file # shouldn't happen
      begin
        http_download temp_file
        FileUtils.cp temp_file, @options[:output]
      ensure
        log 'Cleaning up temp file'
        File.delete temp_file if File.exist? temp_file
      end
    end

    def http_download(temp_file)
      url = create_url

      log "Starting download from: #{url}"
      output = `curl #{create_arg_string} "#{url}" -o #{temp_file} -w '%{http_code}'`

      abort("File download failed: #{output}") if $?.exitstatus != 0
      log 'File download complete'
    end

    def generate_temp_file_path
      temp_hash = Digest::SHA1.hexdigest("#{Time.now.to_i}-#{rand}")[1, 20]
      temp_file = "#{@options[:artifact]}-#{@options[:version]}-#{temp_hash}.#{@options[:extension]}"
      File.join(@options[:temp], temp_file)
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
      "#{@options[:base_url]}#{@rest_path}#{@content_path}?#{param_string}"
    end

    def log(message)
      puts message if @options[:verbose]
    end
  end
end

options = { extension: 'jar', verbose: false, temp: '/tmp'}
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
  opts.on('-t', '--temp DIR', 'Temp dir')                    { |t| options[:temp] = t }
  opts.on('-v', '--verbose', 'Verbose')                      { |v| options[:verbose] = v }
end.parse!

client = Nexus::Client.new(options)
client.download_artifact
