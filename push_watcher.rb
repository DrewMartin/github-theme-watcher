require 'sinatra/base'
require 'json'
require 'set'
require 'fileutils'
require 'httparty'

SECRETS_JSON = JSON.parse(File.read('secrets.json'))
GITHUB_SECRET = SECRETS_JSON['github_secret_token']
HMAC_DIGEST = OpenSSL::Digest.new('sha1')

THEME_DIRS = %w(layout templates snippets assets config locales sections blocks)

THEMES_GIT_DIR = 'themes'

Dir.mkdir(THEMES_GIT_DIR) unless Dir.exists?(THEMES_GIT_DIR)

class PushWatcher < Sinatra::Base
  # set :bind, '0.0.0.0'
  # set :port, 3876

  attr_reader :request_body

  before do
    @request_body = request.body.read
  end

  before do
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(HMAC_DIGEST, GITHUB_SECRET, request_body)
    halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
  end

  post '/push' do
    json_body = JSON.parse(request_body)
    return unless json_body["ref"] == "refs/heads/master"
    upload_theme_changes(json_body)
  end

  private

  def upload_theme_changes(json_body)
    repo_credentials = SECRETS_JSON['themes'][json_body['repository']['full_name']]
    return 404 unless repo_credentials
    commits = json_body['commits']
    return unless commits.is_a?(Array) && !commits.empty?

    changeset = compute_changeset(commits)
    return if changeset[:changed].empty? && changeset[:removed].empty?
    puts changeset
    return 400 unless update_git_dir(json_body)

    repo_dir = File.join(THEMES_GIT_DIR, json_body['repository']['full_name'])
    url = "https://#{repo_credentials['shopify_domain']}/admin/themes/#{repo_credentials['theme_id']}/assets.json"
    options = {
      basic_auth: {
        username: repo_credentials['shopify_credentials']['api_key'],
        password: repo_credentials['shopify_credentials']['password']
      }
    }

    changeset[:changed].each do |changed_file|
      contents = File.read(File.join(repo_dir, changed_file))
      HTTParty.put(url, options.merge({body: {asset: {key: changed_file, value: contents}}}))
    end

    changeset[:removed].each do |changed_file|
      HTTParty.delete(url, options.merge({body: {asset: {key: changed_file}}}))
    end
  end

  def compute_changeset(commits)
    changed = Set.new
    removed = Set.new

    commits.each do |commit|
      (commit["added"] + commit["modified"]).each do |file|
        next unless theme_file?(file)
        changed.add(file)
        removed.delete(file)
      end

      commit['removed'].each do |file|
        next unless theme_file?(file)
        removed.add(file)
        changed.delete(file)
      end
    end

    {changed: changed.to_a, removed: removed.to_a}
  end

  def theme_file?(file)
    THEME_DIRS.include?(File.dirname(file))
  end

  def update_git_dir(json_body)
    repository = json_body['repository']
    repo_dir = File.join(THEMES_GIT_DIR, repository['full_name'])
    unless Dir.exists?(File.join(repo_dir, '.git'))
      system("git clone #{repository['clone_url']} #{repo_dir}")
    end

    # returns true if successful
    system("git -C #{repo_dir} fetch && git -C #{repo_dir} reset --hard #{json_body['after']}")
  end

  # run! if app_file == $0
end
