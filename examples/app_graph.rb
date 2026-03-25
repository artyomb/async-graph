# frozen_string_literal: true

require_relative "../lib/async-graph"

GRAPH = AsyncGraph::Graph.new do
  node :split do
  end

  node :left do
    { left_ready: true }
  end

  node :right do
    { right_ready: true }
  end

  node :merge do |state, await|
    results = await.all(
      profile: [:fetch_profile, {user_id: state[:user_id]}],
      score: [:fetch_score, {user_id: state[:user_id]}]
    )

    {
      left: results[:profile],
      right: results[:score],
      message: "#{results[:profile][:name]} score=#{results[:score][:score]}"
    }
  end

  set_entry_point :split
  edge :split, :left, branch: :left
  edge :split, :right, branch: :right
  edge %i[left right], :merge
  set_finish_point :merge
end

RUNNER = AsyncGraph::Runner.new(GRAPH)
