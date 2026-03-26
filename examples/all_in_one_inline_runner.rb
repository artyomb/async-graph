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

run = runner.start_run state: {left: 7, right: 5, total: 20, discount: 3}

until run.finished?
  run = runner.advance_run(
    run: run,
    resolve_request: lambda do |kind, payload|
      case kind
      when :add then payload[:left] + payload[:right]
      when :subtract then payload[:left] - payload[:right]
      else AsyncGraph::DEFER
      end
    end
  )
end

puts JSON.pretty_generate(run.result)
