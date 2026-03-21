# frozen_string_literal: true

require "json"
require_relative "app_graph"

Dir.chdir(__dir__)

File.write(
  "graph_states.json",
  JSON.pretty_generate(
    AsyncGraph.stringify(
      graphs: [
        {
          graph_uid: "graph-1",
          status: :running,
          tokens: [{token_uid: "t1", node: GRAPH.entry, state: {user_id: 7}, fork_uid: nil, branch: nil, from_node: nil, awaits: {}}],
          joins: {},
          result: nil
        },
        {
          graph_uid: "graph-2",
          status: :running,
          tokens: [{token_uid: "t1", node: GRAPH.entry, state: {user_id: 8}, fork_uid: nil, branch: nil, from_node: nil, awaits: {}}],
          joins: {},
          result: nil
        }
      ]
    )
  ) + "\n"
)
File.write("jobs.json", JSON.pretty_generate(jobs: []) + "\n")

puts "reset"
