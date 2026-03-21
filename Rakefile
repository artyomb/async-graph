# frozen_string_literal: true

require "erb"
require "fileutils"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require_relative "lib/async-graph/version"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec]

desc "CI RSpec run with reports"
task :rspec do
  FileUtils.mkdir_p("results")
  RSpec::Core::RakeTask.new(:ci_spec) do |rspec|
    rspec.rspec_opts = "--profile --color -f documentation " \
      "-f RspecJunitFormatter --out ./results/rspec.xml"
  end
  Rake::Task[:ci_spec].invoke
end

desc "Update README.md from README.erb"
task :readme do
  template = File.read("README.erb")
  renderer = ERB.new(template, trim_mode: "-")
  File.write("README.md", renderer.result)
end

desc "Build and push a new version"
task push: %i[spec readme] do
  gem_name = "async-graph-#{AsyncGraph::VERSION}.gem"

  system("gem build async-graph.gemspec") or exit 1
  system("gem install ./#{gem_name}") or exit 1
  system("gem push #{gem_name}") or exit 1
  system("gem list -r async-graph") or exit 1
end

desc "Build a new version"
task build: %i[spec readme] do
  system("gem build async-graph.gemspec") or exit 1
end
