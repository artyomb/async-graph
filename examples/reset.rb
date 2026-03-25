# frozen_string_literal: true

require "json"
require_relative "app_graph"

Dir.chdir(__dir__)

File.write(
  "graph_states.json",
  JSON.pretty_generate(
    graphs: [
      {
        graph_uid: "graph-1",
        run: RUNNER.start_run(state: {user_id: 7}).to_h
      },
      {
        graph_uid: "graph-2",
        run: RUNNER.start_run(state: {user_id: 8}).to_h
      }
    ]
  ) + "\n"
)
File.write("jobs.json", JSON.pretty_generate(jobs: []) + "\n")

puts "reset"
