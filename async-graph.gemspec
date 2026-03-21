# frozen_string_literal: true

require_relative "lib/async-graph/version"

Gem::Specification.new do |spec|
  spec.name = "async-graph"
  spec.version = AsyncGraph::VERSION
  spec.summary = "Async Graph runtime with external job scheduling"
  spec.description = "A minimal Ruby graph runtime that suspends on external work and resumes later."
  spec.authors = ["Artem Borodkin"]
  spec.email = ["author@email.address"]
  spec.files = Dir[
    "{bin,examples,lib,spec}/**/*",
    ".github/workflows/*",
    ".gitignore",
    ".rspec",
    ".rubocop.yml",
    ".ruby-version",
    "Gemfile",
    "Rakefile",
    "README.erb",
    "README.md",
    "async-graph.gemspec"
  ]
  spec.require_paths = ["lib"]
  spec.homepage = "https://rubygems.org/gems/async-graph"
  spec.license = "MIT"
  spec.metadata = { "source_code_uri" => "https://github.com/artyomb/async-graph" }
  # spec.required_ruby_version = ">= #{File.read(File.join(__dir__, ".ruby-version")).strip}"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.10"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.5.1"
  spec.add_development_dependency "rubocop", "~> 1.12"
  spec.add_development_dependency "rubocop-rake", "~> 0.6.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.14.2"
end
