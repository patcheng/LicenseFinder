require 'fileutils'
require 'pathname'
require 'bundler'
require 'capybara'

module LicenseFinder::TestingDSL
  class User
    def run_license_finder
      execute_command "license_finder --quiet"
    end

    def create_empty_project
      reset_projects!
      app_path.mkpath
    end

    def create_python_app
      create_empty_project

      shell_out("cd #{app_path} && touch requirements.txt")

      add_pip_dependency('argparse==1.2.1')

      pip_install
    end

    def create_node_app
      create_empty_project

      shell_out("cd #{app_path} && touch package.json")

      add_npm_dependency('http-server', '0.6.1')

      npm_install
    end

    def create_bower_app
      create_empty_project

      shell_out("cd #{app_path} && touch bower.json")

      add_bower_dependency('gmaps', '0.2.30')

      bower_install
    end

    def create_maven_app
      create_empty_project

      add_maven_dependency

      mvn_install
    end

    def create_gradle_app
      create_empty_project

      add_gradle_dependency
    end

    def create_ruby_app
      reset_projects!

      shell_out("cd #{projects_path} && bundle gem #{app_name}")

      add_gem_dependency('license_finder', path: root_path.to_s)

      bundle_install
    end

    def create_cocoapods_app
      create_empty_project

      add_pod_dependency

      pod_install
    end

    def create_gem(gem_name, options)
      gem_dir = projects_path.join(gem_name)

      gem_dir.mkpath
      gem_dir.join("#{gem_name}.gemspec").open('w') do |file|
        file.write gemspec_string(gem_name, options)
      end
    end

    def depend_on_local_gem(gem_name, options={})
      gem_dir = projects_path.join(gem_name)
      options[:path] = gem_dir.to_s

      add_gem_dependency(gem_name, options)

      bundle_install
    end

    def execute_command(command)
      ::Bundler.with_clean_env do
        @output = shell_out("cd #{app_path} && bundle exec #{command}", true)
      end
    end

    def seeing?(content)
      @output.include? content
    end

    def seeing_line?(content)
      seeing_something_like? /^#{Regexp.escape content}$/
    end

    def seeing_something_like?(regex)
      @output =~ regex
    end

    def receiving_exit_code?(code)
      @last_command_exit_status.exitstatus == code
    end

    def in_html
      yield Capybara.string(@output)
    end

    def in_dep_html(dep_name)
      in_html do |page|
        yield page.find("##{dep_name}")
      end
    end

    def html_title
      in_html { |page| page.find("h1") }
    end

    private

    def gemspec_string(gem_name, options)
      if options.has_key?(:license) && options.has_key?(:licenses)
        raise "Can't specify both `license` and `licenses`"
      end

      license_key = ([:license, :licenses] & options.keys).first
      license_value = options.fetch(license_key)
      summary = options.fetch(:summary, "")
      description = options.fetch(:description, "")
      version = options[:version] || "0.0.0"
      homepage = options[:homepage]

      <<-GEMSPEC
      Gem::Specification.new do |s|
        s.name = "#{gem_name}"
        s.version = "#{version}"
        s.author = "Cucumber"
        s.summary = "#{summary}"
        s.#{license_key} = #{license_value.inspect}
        s.description = "#{description}"
        s.homepage = "#{homepage}"
      end
      GEMSPEC
    end

    def add_gem_dependency(name, options = {})
      line = "gem #{name.inspect}"
      line << ", " + options.inspect unless options.empty?

      add_to_file("Gemfile", line)
    end

    def add_pip_dependency(dependency)
      add_to_file("requirements.txt", dependency)
    end

    def add_npm_dependency(dependency, version)
      line = "{\"dependencies\" : {\"#{dependency}\": \"#{version}\"}}"
      add_to_file("package.json", line)
    end

    def add_bower_dependency(dependency, version)
      line = "{\"name\": \"my_app\", \"dependencies\" : {\"#{dependency}\": \"#{version}\"}}"
      add_to_file('bower.json', line)
    end

    def add_maven_dependency
      path = fixtures_path.join("pom.xml")
      shell_out("cp #{path} #{app_path}")
    end

    def add_gradle_dependency
      path = fixtures_path.join("build.gradle")
      shell_out("cd #{app_path} && cp #{path} .")
    end

    def add_pod_dependency
      path = fixtures_path.join("Podfile")
      shell_out("cp #{path} #{app_path}")
    end

    def bundle_install
      ::Bundler.with_clean_env do
        shell_out("cd #{app_path} && bundle check || bundle install")
      end
    end

    def pip_install
      shell_out("cd #{app_path} && pip install -r requirements.txt")
    end

    def npm_install
      shell_out("cd #{app_path} && npm install 2>/dev/null")
    end

    def bower_install
      shell_out("cd #{app_path} && bower install 2>/dev/null")
    end

    def mvn_install
      shell_out("cd #{app_path} && mvn install")
    end

    def pod_install
      shell_out("cd #{app_path} && pod install --no-integrate")
    end

    def add_to_file(filename, line)
      shell_out("echo #{line.inspect} >> #{app_path.join(filename)}")
    end

    def app_name
      "my_app"
    end

    def app_path(sub_directory = nil)
      path = base_path = projects_path.join(app_name).cleanpath

      if sub_directory
        path = base_path.join(sub_directory).cleanpath

        raise "#{sub_directory} is outside of the app" unless path.to_s =~ %r{^#{base_path}/}
      end

      path
    end

    def sandbox_path
      root_path.join("tmp")
    end

    def projects_path
      sandbox_path.join("projects")
    end

    def fixtures_path
      root_path.join("spec", "fixtures")
    end

    def reset_projects!
      shell_out("rm -rf #{projects_path}")
      projects_path.mkpath
    end

    def root_path
      Pathname.new(__FILE__).dirname.join("..", "..").realpath
    end

    def shell_out(command, allow_failures = false)
      output = `#{command} 2>&1`
      status = $?
      unless status.success? || allow_failures
        message_format = <<EOM
Command failed: `%s`
output: %s
exit: %d
EOM
        message = sprintf message_format, command, output.chomp, status.exitstatus
        raise RuntimeError.new(message)
      end

      @last_command_exit_status = status
      output
    end
  end
end
