class SubtreeDeploy
  require 'shellwords'
  require 'tempfile'
  require 'fileutils'

  def initialize(options)
    @revision_file = File.expand_path(options[:revision_file] || "REVISION")
    @prefix = options[:prefix] || "subtree"
    @repository = options[:repository]
    unless @repository
      raise ArgumentError, ":repository options are required"
    end
    @branch = options[:branch] || "master"
    @remote_name = options[:remote_name] || "subtree"
    @build_dir = options[:build_dir] || ".build"
    @git_command = options[:git_command] || "git"
    @source_root = File.expand_path('.')
  end

  attr_reader :revision_file, :repository, :branch, :remote_name
  attr_reader :prefix, :source_root, :build_dir

  def current_revision
    if File.exists?(@revision_file)
      File.read(@revision_file).strip
    else
      nil
    end
  end

  def next_revision
    git_cmdout("rev-parse #{e @remote_name}/#{e @branch}").strip
  end

  def setup!
    git "remote add #{e @remote_name} #{e @repository}"
    git "fetch #{e @remote_name}"
    return self
  end

  def clean!
    git "remote remove #{e @remote_name}"
    return self
  end

  #
  # Update subtree.
  #
  # This method deletes all files in :prefix first so that it doesn't cause
  # subtree-merge. After updating the files, it updates :revision_file to store
  # the updated commit hash.
  #
  def update(commit=nil)
    # setup if necessary
    begin
      git "remote show | grep -q #{e @remote_name}"
    rescue
      setup!
    end

    # fetch changes
    git "fetch #{e @remote_name}"

    # clean prefix first to not cause merge
    git "rm -rf #{ep @prefix} >/dev/null 2>&1 || true"
    FileUtils.rm_rf "#{ep @prefix}"

    # update prefix
    treeish = commit || "#{@remote_name}/#{@branch}"
    git "read-tree --prefix=#{ep @prefix} #{e treeish}"
    git "checkout #{ep @prefix}"

    # save last revision
    @last_revision = current_revision || git_cmdout("rev-list --max-parents=0 #{e @remote_name}/#{e @branch}").strip

    # update revision file
    revision = git_cmdout("rev-parse #{e treeish}").strip
    File.write(@revision_file, revision)
    git "add #{ep @revision_file}"

    return self
  end

  #
  # Commit subtree to the git tree.
  #
  # Call this method after update. Otherwise this does nothing.
  #
  def commit_update!(options={})
    file = create_update_message_file("Updated #{@remote_name} to ", @last_revision, current_revision)

    # commit changes
    extra_files = options[:extra_files] || []
    git "commit #{ep @prefix} #{ep @revision_file}#{extra_files.map {|f| " #{ep f}" }.join} -F #{ep file.path}"

    file.delete

    return self
  end

  def create_update_message_file(message, from_revision, to_revision)
    file = Tempfile.new("subtree-deploy-message")
    file.write message

    file.write git_cmdout("show #{to_revision} --pretty='format:%H %ad' | head -n 1").strip

    # create commit comment file
    if from_revision
      file.puts ""
      file.write git_cmdout("log #{from_revision}..#{to_revision} --pretty='format:%h %s'")
    end
    file.close

    puts File.read(file.path)
    puts ""

    return file
  end
  private :create_update_message_file

  #
  # Prepare clean source tree for build in a subdirectory.
  #
  # Callers can pass actual build (and/or test) code to the &block.
  #
  def build(dest_branch, &block)
    current_commit = git_cmdout("rev-parse HEAD").strip

    sh "rm -rf #{e @build_dir}"
    git "clone . #{e @build_dir}"
    sh "cp -f #{e File.join('.git', 'config')} #{e File.join(@build_dir, '.git')}"

    Dir.chdir(@build_dir) do
      git "fetch origin"

      git "branch -D #{e dest_branch}" rescue nil
      begin
        git "checkout #{e dest_branch}"
        # tracked_branch
      rescue
        git "checkout -b #{e dest_branch} #{e current_commit}"
      end

      # copy latest code to the deploy branch.
      git "checkout #{e current_commit} -- ."

      block.call if block

      # add the latest code to the deploy branch.
      git "add -f ."
    end

    return self
  end

  def commit_build!
    current_commit = git_cmdout("rev-parse HEAD").strip

    Dir.chdir(@build_dir) do
      last_commit = git_cmdout("rev-parse HEAD").strip

      file = create_update_message_file("Updated #{@remote_name} to ", last_commit, current_commit)

      begin
        git "commit -a -F #{ep file.path}"
      rescue
        # git-commit fails if there're no changes
      end

      file.delete
    end

    return self
  end

  #
  # Push built files in the subdirectory to a given remote branch.
  #
  # Call this method after #build and #commit_build!. Otherwise push_build!
  # does nothing or fails since the subdirectory does not exist.
  #
  def push_build!(dest_branch)
    Dir.chdir(@build_dir) do
      git "checkout #{e dest_branch}"

      begin
        git_cmdout "rev-parse --abbrev-ref #{e dest_branch}@{u}"
        tracked_branch = true
      rescue
        tracked_branch = false
      end

      if tracked_branch
        git "push origin #{e dest_branch}:#{e dest_branch}"
      else
        git "push origin #{e dest_branch}"
      end
    end

    return nil
  end

  def git(args)
    sh "#{e @git_command} #{args}"
  end

  def git_cmdout(args)
    sh_cmdout "#{e @git_command} #{args}"
  end

  private

  def sh(cmd)
    puts "> #{cmd}"
    system cmd
    unless $?.success?
      raise "Command failed #{$?.to_i}"
    end
  end

  def sh_cmdout(cmd)
    puts "> #{cmd}"
    out = `#{cmd}`
    unless $?.success?
      raise "Command failed #{$?.to_i}"
    end
    return out
  end

  def ep(s)
    base = File.expand_path(".")
    s = s.sub(/^#{Regexp.escape(base)}\/?/, '')
    Shellwords.escape(s)
  end

  def e(s)
    Shellwords.escape(s)
  end
end
