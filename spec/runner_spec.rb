# frozen_string_literal: true

RSpec.describe AsyncGraph::Runner do
  it "creates a start token from the graph entry point" do
    graph = AsyncGraph::Graph.new do
      node :start do
      end

      set_entry_point :start
    end

    token = described_class.new(graph).start(state: {user_id: 7})

    expect(token).to eq(
      token_uid: "t1",
      node: :start,
      state: {user_id: 7},
      fork_uid: nil,
      branch: nil,
      source_node: nil,
      awaits: {}
    )
  end

  it "builds an opaque persisted run from the entry point" do
    graph = AsyncGraph::Graph.new do
      node :start do
      end

      set_entry_point :start
    end

    run = described_class.new(graph).start_run(state: {user_id: 7})

    aggregate_failures do
      expect(run).to be_running
      expect(run.result).to be_nil
      expect(run.to_h).to eq(
        status: "running",
        tokens: [
          {
            token_uid: "t1",
            node: :start,
            state: {user_id: 7},
            fork_uid: nil,
            branch: nil,
            source_node: nil,
            awaits: {}
          }
        ],
        joins: {},
        result: nil
      )
    end
  end

  it "spawns branch tokens for fan-out and finishes on finish edges" do
    graph = AsyncGraph::Graph.new do
      node :split do
      end

      node :left do
        {left_ready: true}
      end

      node :right do
        {right_ready: true}
      end

      set_entry_point :split
      edge :split, :left, branch: :left
      edge :split, :right, branch: :right
      set_finish_point :left
      set_finish_point :right
    end

    runner = described_class.new(graph)
    split = runner.step(
      token: runner.start(state: {user_id: 7}),
      joins: {}
    )

    aggregate_failures do
      expect(split).to be_advanced
      expect(split.tokens).to eq(
        [
          {
            token_uid: "t1.left",
            node: :left,
            state: {user_id: 7},
            fork_uid: "fork-t1",
            branch: :left,
            source_node: :split,
            awaits: {}
          },
          {
            token_uid: "t1.right",
            node: :right,
            state: {user_id: 7},
            fork_uid: "fork-t1",
            branch: :right,
            source_node: :split,
            awaits: {}
          }
        ]
      )
    end

    left = runner.step(token: split.tokens.first, joins: split.joins)
    right = runner.step(token: split.tokens.last, joins: split.joins)

    aggregate_failures do
      expect(left).to be_finished
      expect(left.state).to eq(user_id: 7, left_ready: true)
      expect(right).to be_finished
      expect(right.state).to eq(user_id: 7, right_ready: true)
    end
  end

  it "advances a persisted run without exposing joins to the caller" do
    graph = AsyncGraph::Graph.new do
      node :split do
      end

      node :left do
        {left_ready: true}
      end

      node :right do
        {right_ready: true}
      end

      node :merge do |state, await|
        profile = await.call(:profile, :fetch_profile, user_id: state[:user_id])
        {profile: profile}
      end

      set_entry_point :split
      edge :split, :left, branch: :left
      edge :split, :right, branch: :right
      edge %i[left right], :merge
      set_finish_point :merge
    end

    runner = described_class.new(graph)
    run = runner.start_run(state: {user_id: 7})
    run1 = runner.advance_run(run: run)
    run2 = runner.advance_run(run: run1)
    run3 = runner.advance_run(run: run2)
    run4 = runner.advance_run(run: run3) { |_| "job-1" }
    run5 = runner.advance_run(
      run: run4,
      resolved_for: ->(token) { token[:awaits][:profile] == "job-1" ? {"profile" => {id: 7, name: "Ada"}} : {} }
    )

    aggregate_failures do
      expect(run1.tokens.map { |token| token[:token_uid] }).to eq(%w[t1.left t1.right])
      expect(run2.tokens.map { |token| token[:node] }).to eq(%i[merge merge])
      expect(run3.tokens.map { |token| token[:token_uid] }).to eq(["fork-t1.join"])
      expect(run4.tokens.first.fetch(:awaits)).to eq(profile: "job-1")
      expect(run5).to be_finished
      expect(run5.result).to eq(
        user_id: 7,
        left_ready: true,
        right_ready: true,
        profile: {id: 7, name: "Ada"}
      )
    end
  end

  it "finishes a run inline when resolve_request handles all awaits" do
    graph = AsyncGraph::Graph.new do
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

    runner = described_class.new(graph)
    run = runner.advance_run(
      run: runner.start_run(state: {left: 7, right: 5, total: 20, discount: 3}),
      resolve_request: lambda do |kind, payload|
        case kind
        when :add then payload[:left] + payload[:right]
        when :subtract then payload[:left] - payload[:right]
        else AsyncGraph::DEFER
        end
      end
    )

    aggregate_failures do
      expect(run).to be_finished
      expect(run.result).to eq(
        left: 7,
        right: 5,
        total: 20,
        discount: 3,
        added: 12,
        subtracted: 17,
        answer: -5
      )
    end
  end

  it "binds only deferred requests when resolve_request handles part of await.all inline" do
    graph = AsyncGraph::Graph.new do
      node :calculate do |state, await|
        results = await.all(
          added: [:add, {left: state[:left], right: state[:right]}],
          discounted: [:discount, {total: state[:total], amount: state[:discount]}]
        )

        {
          added: results[:added],
          discounted: results[:discounted]
        }
      end

      set_entry_point :calculate
      set_finish_point :calculate
    end

    resolve_request = lambda do |kind, payload|
      case kind
      when :add then payload[:left] + payload[:right]
      else AsyncGraph::DEFER
      end
    end

    runner = described_class.new(graph)
    first = runner.advance_run(
      run: runner.start_run(state: {left: 7, right: 5, total: 20, discount: 3}),
      resolved: ->(*) {},
      resolve_request: resolve_request
    ) { |request| "job-#{request.key}" }

    finished = runner.advance_run(
      run: first,
      resolved: lambda do |token|
        token[:awaits][:discounted] == "job-discounted" ? {"discounted" => 17} : {}
      end,
      resolve_request: resolve_request
    )

    aggregate_failures do
      expect(first).to be_running
      expect(first.tokens.first.fetch(:awaits)).to eq(discounted: "job-discounted")
      expect(finished).to be_finished
      expect(finished.result).to eq(
        left: 7,
        right: 5,
        total: 20,
        discount: 3,
        added: 12,
        discounted: 17
      )
    end
  end

  it "reuses existing request bindings when a suspended token is retried" do
    graph = AsyncGraph::Graph.new do
      node :fetch do |state, await|
        user = await.call(:user, :fetch_user, user_id: state[:user_id])
        {user: user}
      end

      set_entry_point :fetch
      set_finish_point :fetch
    end

    runner = described_class.new(graph)
    first = runner.step(token: runner.start(state: {user_id: 7}), joins: {}) { |_| "job-1" }
    second = runner.step(token: first.token, joins: first.joins)
    finished = runner.step(
      token: first.token,
      joins: first.joins,
      resolved: {"user" => {id: 7, name: "Ada"}}
    )

    aggregate_failures do
      expect(first).to be_suspended
      expect(first.token.fetch(:awaits)).to eq(user: "job-1")
      expect(second).to be_suspended
      expect(second.token.fetch(:awaits)).to eq(user: "job-1")
      expect(second.request_refs).to eq(user: "job-1")
      expect(finished).to be_finished
      expect(finished.state).to eq(
        user_id: 7,
        user: {id: 7, name: "Ada"}
      )
    end
  end

  it "parks and releases join tokens through the runner" do
    graph = AsyncGraph::Graph.new do
      node :split do
      end

      node :left do
        {left_ready: true}
      end

      node :right do
        {right_ready: true}
      end

      node :merge do
      end

      set_entry_point :split
      edge :split, :left, branch: :left
      edge :split, :right, branch: :right
      edge %i[left right], :merge
    end

    runner = described_class.new(graph)
    split = runner.step(
      token: runner.start(state: {user_id: 7}),
      joins: {}
    )
    left = runner.step(token: split.tokens.first, joins: split.joins)
    right = runner.step(token: split.tokens.last, joins: split.joins)
    parked = runner.step(token: left.token, joins: left.joins)
    released = runner.step(token: right.token, joins: parked.joins)

    aggregate_failures do
      expect(parked).to be_parked
      expect(parked.joins.keys).to eq([:'fork-t1:merge'])
      expect(released).to be_released
      expect(released.tokens).to eq(
        [
          {
            token_uid: "fork-t1.join",
            node: :merge,
            state: {user_id: 7, left_ready: true, right_ready: true},
            fork_uid: nil,
            branch: nil,
            source_node: nil,
            awaits: {}
          }
        ]
      )
      expect(released.joins).to eq({})
    end
  end
end
