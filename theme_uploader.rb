require 'httparty'
require 'open3'

THEMES_GIT_DIR = 'themes'
THEME_BUCKETS = %w(layout templates snippets assets config locales sections blocks)

class ThemeUploader
  attr_reader :json, :credentials, :logger

  def initialize(credentials, json, logger)
    @logger = logger
    @json = json
    @credentials = credentials
  end

  def process_commits
    return logger.info "No commits found in changes" if no_commits?
    return logger.info "No net change to theme assets found" if no_asset_changes?
    unless update_git_dir
      return "failed to update git dir"
    end

    logger.info "Changeset: \n#{JSON.pretty_generate(changeset)}"

    upload_theme_changes
  end

  private

  def upload_theme_changes
    debugger
    url = "https://#{credentials['shopify_domain']}/admin/themes/#{theme_id}/assets.json"
    options = {
      basic_auth: {
        username: credentials['shopify_credentials']['api_key'],
        password: credentials['shopify_credentials']['password']
      }
    }

    changeset[:changed].each do |changed_file|
      contents = File.read(File.join(repository_dir, changed_file))
      response = HTTParty.put(url, options.merge({body: {asset: {key: changed_file, value: contents}}}))
      if response.code < 400
        logger.info "Successfully uploaded #{changed_file} to theme #{theme_id}"
      else
        logger.error "Failed to upload #{changed_file} with code #{response.code} to theme #{theme_id}: #{response.body}"
      end
    end

    changeset[:removed].each do |removed_file|
      response = HTTParty.delete(url, options.merge({body: {asset: {key: removed_file}}}))
      if response.code < 400
        logger.info "Successfully deleted #{removed_file} from theme #{theme_id}"
      else
        logger.error "Failed to delete #{removed_file} with code #{response.code} from theme #{theme_id}: #{response.body}"
      end
    end
  end

  def changeset
    @changeset ||= compute_changeset
  end

  def compute_changeset
    changed = Set.new
    removed = Set.new

    commits.each do |commit|
      (commit["added"] + commit["modified"]).each do |file|
        next unless theme_asset?(file)
        changed.add(file)
        removed.delete(file)
      end

      commit['removed'].each do |file|
        next unless theme_asset?(file)
        removed.add(file)
        changed.delete(file)
      end
    end

    {changed: changed.to_a, removed: removed.to_a}
  end

  def update_git_dir
    unless Dir.exists?(repository_dir)
      return unless exec_and_log("git clone #{repository_info['clone_url']} #{repository_dir}")
    end

    exec_and_log("git -C #{repository_dir} fetch") &&
      exec_and_log("git -C #{repository_dir} reset --hard #{json['after']}")
  end

  # execute system command, logging stdio to logger.info and stderr to logger.error
  # returns whether the command ran successfully
  def exec_and_log(command)
    stdout_err, status = Open3.capture2e(command)
    if status.success?
      logger.info "Running command #{command}: #{stdout_err}"
    else
      logger.error "Error running command #{command}: #{stdout_err}"
    end
    status.success?
  end

  def theme_asset?(file)
    THEME_BUCKETS.include?(File.dirname(file))
  end

  def repository_info
    @repository_info ||= json.fetch('repository', {})
  end

  def repository_dir
    @repository_dir ||= File.join(THEMES_GIT_DIR, repository_info['full_name'])
  end

  def commits
    @commits ||= json.fetch('commits', [])
  end

  def theme_id
    @theme_id ||= credentials['theme_id']
  end

  def no_commits?
    !commits.is_a?(Array) || commits.empty?
  end

  def no_asset_changes?
    changeset[:changed].empty? && changeset[:removed].empty?
  end
end
