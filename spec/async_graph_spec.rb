# frozen_string_literal: true

RSpec.describe AsyncGraph::Graph do
  it "suspends and resumes await.all in one node" do
    graph = described_class.new do
      node :merge do |state, await|
        results = await.all(
          profile: [:fetch_profile, {user_id: state[:user_id]}],
          score: [:fetch_score, {user_id: state[:user_id]}]
        )

        {
          profile: results[:profile],
          score: results[:score]
        }
      end

      set_entry_point :merge
      set_finish_point :merge
    end

    step = graph.step(state: {user_id: 7}, node: graph.entry)

    aggregate_failures do
      expect(step).to be_a(AsyncGraph::Suspended)
      expect(step.requests.map(&:key)).to eq(%w[profile score])
      expect(step.requests.map(&:kind)).to eq(%i[fetch_profile fetch_score])
    end

    resumed = graph.step(
      state: step.state,
      node: step.node,
      resolved: {
        "profile" => {name: "Ada"},
        "score" => {score: 70}
      }
    )

    aggregate_failures do
      expect(resumed).to be_a(AsyncGraph::Advanced)
      expect(resumed.state).to eq(
        user_id: 7,
        profile: {name: "Ada"},
        score: {score: 70}
      )
      expect(resumed.destinations.map(&:to)).to eq([AsyncGraph::FINISH])
    end
  end

  it "builds a barrier edge from multiple sources" do
    graph = described_class.new do
      node :left do
      end

      node :right do
      end

      node :merge do
      end

      set_entry_point :left
      edge %i[left right], :merge
    end

    aggregate_failures do
      expect(graph.join?(:merge)).to eq(true)
      expect(graph.join_for(:merge)).to eq(%i[left right])
      expect(graph.edges_from(:left).map(&:to)).to eq([:merge])
      expect(graph.edges_from(:right).map(&:to)).to eq([:merge])
    end
  end

  it "applies command updates and explicit goto" do
    graph = described_class.new do
      node :start do
        AsyncGraph::Command.update_and_goto({ok: true}, :done)
      end

      node :done do
      end

      set_entry_point :start
      set_finish_point :done
    end

    step = graph.step(state: {}, node: graph.entry)

    aggregate_failures do
      expect(step).to be_a(AsyncGraph::Advanced)
      expect(step.state).to eq(ok: true)
      expect(step.destinations.map(&:to)).to eq([:done])
    end
  end

  it "validates that an entry point exists before execution" do
    graph = described_class.new do
      node :start do
      end
    end

    expect do
      graph.step(state: {}, node: :start)
    end.to raise_error(AsyncGraph::ValidationError, /Entry point is not set/)
  end

  it "validates graph edges before execution" do
    graph = described_class.new do
      node :start do
      end

      set_entry_point :start
      edge :start, :missing
    end

    expect do
      graph.step(state: {}, node: graph.entry)
    end.to raise_error(AsyncGraph::ValidationError, /Edge target missing is not defined/)
  end

  it "rejects duplicate node definitions" do
    expect do
      described_class.new do
        node :start do
        end

        node :start do
        end
      end
    end.to raise_error(AsyncGraph::ValidationError, /Node start is already defined/)
  end

  it "parks and releases join tokens inside the library" do
    graph = described_class.new do
      node :left do
      end

      node :right do
      end

      node :merge do
      end

      set_entry_point :left
      edge %i[left right], :merge
    end

    parked = graph.process_join(
      token: {
        token_uid: "t1.left",
        node: :merge,
        state: {user_id: 7, left_ready: true},
        fork_uid: "fork-1",
        branch: :left,
        source_node: :left,
        awaits: {}
      },
      joins: {}
    )

    expect(parked).to be_a(AsyncGraph::JoinParked)
    expect(parked.joins.keys).to eq([:'fork-1:merge'])

    released = graph.process_join(
      token: {
        token_uid: "t1.right",
        node: :merge,
        state: {user_id: 7, right_ready: true},
        fork_uid: "fork-1",
        branch: :right,
        source_node: :right,
        awaits: {}
      },
      joins: parked.joins
    )

    aggregate_failures do
      expect(released).to be_a(AsyncGraph::JoinReleased)
      expect(released.joins).to eq({})
      expect(released.token.fetch(:token_uid)).to eq("fork-1.join")
      expect(released.token.fetch(:node)).to eq(:merge)
      expect(released.token.fetch(:state)).to eq(
        user_id: 7,
        left_ready: true,
        right_ready: true
      )
    end
  end

  it "raises when join branches disagree on the same state key" do
    graph = described_class.new do
      node :left do
      end

      node :right do
      end

      node :merge do
      end

      set_entry_point :left
      edge %i[left right], :merge
    end

    parked = graph.process_join(
      token: {
        token_uid: "t1.left",
        node: :merge,
        state: {shared: 1},
        fork_uid: "fork-1",
        branch: :left,
        source_node: :left,
        awaits: {}
      },
      joins: {}
    )

    expect do
      graph.process_join(
        token: {
          token_uid: "t1.right",
          node: :merge,
          state: {shared: 2},
          fork_uid: "fork-1",
          branch: :right,
          source_node: :right,
          awaits: {}
        },
        joins: parked.joins
      )
    end.to raise_error(AsyncGraph::JoinConflictError, /shared/)
  end

  it "validates explicit goto targets when commands are applied" do
    graph = described_class.new do
      node :start do
        AsyncGraph::Command.goto(:missing)
      end

      set_entry_point :start
    end

    expect do
      graph.step(state: {}, node: graph.entry)
    end.to raise_error(AsyncGraph::ValidationError, /Goto target missing is not defined/)
  end
end
