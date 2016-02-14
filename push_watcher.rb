require 'sinatra/base'
require 'json'
require 'set'
require './theme_uploader'

SECRETS_JSON = JSON.parse(File.read('secrets.json'))
HMAC_DIGEST = OpenSSL::Digest.new('sha1')

class PushWatcher < Sinatra::Base
  attr_reader :request_body
  attr_reader :json
  attr_reader :repo_credentials

  configure :production, :development do
    enable :logging
  end

  before do
    @request_body = request.body.read
    message = "#{request.request_method} to #{request.path}"
    begin
      @json = JSON.parse(request_body)
      logger.info message + " with \n#{JSON.pretty_generate(@json)}"
    rescue JSON::ParserError
      log_error_and_halt message + " with bad json: %p" % request_body
    ensure

    end
  end

  before do
    repository = json['repository']
    unless repository
      log_error_and_halt "repository missing from request"
    end

    repo_full_name = repository['full_name']
    unless @repo_credentials = SECRETS_JSON['themes'][repo_full_name]
      log_error_and_halt "No credentials configured for repo #{repo_full_name}"
    end
  end

  before do
    unless header_sig = request.env['HTTP_X_HUB_SIGNATURE']
      log_error_and_halt "Missing signature"
    end

    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(HMAC_DIGEST, repo_credentials["github_secret_token"], request_body)
    unless Rack::Utils.secure_compare(signature, header_sig)
      logger.warn "Signatures don't match. Header '#{request.env['HTTP_X_HUB_SIGNATURE']}' computed '#{signature}'"
      halt 400, "Signatures didn't match!"
    end
  end

  post '/push' do
    unless master_branch?
      logger.info "Push to non-master branches ignored (found #{json['ref']})"
      return 200
    end
    upload_theme_changes
  end

  private

  def log_error_and_halt(message, status: 400)
    logger.error message
    halt status, message
  end

  def master_branch?
    json['ref'] == "refs/heads/master"
  end

  def upload_theme_changes
    Thread.new(repo_credentials, json, logger) do |*args|
      ThemeUploader.new(*args).process_commits
    end
  end
end
