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

    def compare_checksum
      unless File.exist? @options[:output]
        log 'No file found to compare checksum'
        exit 1
      end

      nexus_checksum = http_checksum
      file_checksum = Digest::SHA1.file(@options[:output]).hexdigest

      if file_checksum == nexus_checksum
        log 'Checksum of file matches Nexus'
        exit 0
      else
        log 'Checksum of file does not match Nexus'
        exit 1
      end
    end

    def http_checksum
      @options[:extension] = "#{@options[:extension]}.sha1"
      url = create_url
      log "Fetching checksum from: #{url}"
      checksum = `curl #{create_arg_string} "#{url}"`
      abort('Checksum download failed') if $?.exitstatus != 0
      abort('Checksum malformed') unless checksum =~ /^[a-fA-F0-9]{40}$/
      checksum
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
      `curl #{create_arg_string} "#{url}" -o #{temp_file}`
      $?.exitstatus == 0 ? log('File download complete') : abort('File download failed')
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
  opts.banner = <<EOF
This script will fetch an artifact from a Nexus server using the Nexus REST service

-x Checksum comparison, artifact will not be downloaded:
   Checksum of the file on the file system is compared against the checksum in nexus
   exitcode 0 = match
   exitcode 1 = mismatch

EOF
  opts.on('-n URL', 'Nexus base url')               { |n| options[:base_url] = n }
  opts.on('-u USER', 'Nexus username')              { |u| options[:username] = u }
  opts.on('-p PASS', 'Nexus password')              { |p| options[:password] = p }
  opts.on('-m', 'Use .netrc')                       { |m| options[:netrc] = m }
  opts.on('-g GAV', 'group:artifact:version')       { |a| options[:gav] = a }
  opts.on('-r REPO', 'Repository')                  { |r| options[:repository] = r }
  opts.on('-e EXT', 'Artifact Extension')           { |e| options[:extension] = e }
  opts.on('-c CLASS', 'Artifact Classifier')        { |c| options[:classifier] = c }
  opts.on('-o FILE', 'Output file')                 { |o| options[:output] = o }
  opts.on('-t DIR', 'Temp dir')                     { |t| options[:temp] = t }
  opts.on('-v', 'Verbose')                          { |v| options[:verbose] = v }
  opts.on('-x', 'Compare file checksum with Nexus') { |x| options[:compare] = x }
end.parse!

client = Nexus::Client.new(options)
if options[:compare]
  client.compare_checksum
else
  client.download_artifact
end
