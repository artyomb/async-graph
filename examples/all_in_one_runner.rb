# frozen_string_literal: true

require "json"
require_relative "../lib/async-graph"

runner = AsyncGraph::Runner.new(
  AsyncGraph::Graph.new do
    node :calculate do |state, await|
      results = await.all(
        added: [:add, {left: state[:left], right: state[:right]}],
        subtracted: [:subtract, {left: state[:total], right: state[:discount]}]
      )

      {
        added: results[:added],
        subtracted: results[:subtracted],
        answer: results[:added] - results[:subtracted]
      }
    end

    set_entry_point :calculate
    set_finish_point :calculate
  end
)

results = {}
run = runner.start_run state: {left: 7, right: 5, total: 20, discount: 3}

until run.finished?
  run = runner.advance_run(
    run: run,
    resolved_for: lambda do |token|
      token[:awaits].each_with_object({}) do |(key, request_id), memo|
        memo[key.to_s] = results[request_id] if results.key?(request_id)
      end
    end
  ) do |request|
    results[request.key] =
      case request.kind
      when :add then request.payload[:left] + request.payload[:right]
      when :subtract then request.payload[:left] - request.payload[:right]
      end

    request.key
  end
end

puts JSON.pretty_generate(run.result)
