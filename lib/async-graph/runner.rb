# frozen_string_literal: true

module AsyncGraph
  class Runner
    Run = Struct.new(:status, :tokens, :joins, :result, keyword_init: true) do
      def running? = status.to_sym == :running
      def finished? = status.to_sym == :finished

      def to_h
        {
          status: status.to_s,
          tokens: tokens,
          joins: joins,
          result: result
        }
      end
    end

    Result = Struct.new(:status, :tokens, :joins, :state, :requests, :request_refs, keyword_init: true) do
      def token = tokens.first
      def parked? = status == :parked
      def released? = status == :released
      def suspended? = status == :suspended
      def advanced? = status == :advanced
      def finished? = status == :finished
    end

    def initialize(graph)
      @graph = graph
    end

    def start(state:, token_uid: "t1")
      @graph.validate!

      {
        token_uid: token_uid,
        node: @graph.entry,
        state: state,
        fork_uid: nil,
        branch: nil,
        source_node: nil,
        awaits: {}
      }
    end

    def start_run(state:, token_uid: "t1")
      Run.new(
        status: :running,
        tokens: [start(state:, token_uid:)],
        joins: {},
        result: nil
      )
    end

    def step(token:, joins:, resolved: {}, resolve_request: nil, &)
      return build_join_result(@graph.process_join(token:, joins:)) if join_token?(token)

      graph_step = @graph.step(
        state: token.fetch(:state),
        node: token.fetch(:node),
        resolved: resolved,
        resolve_request: resolve_request
      )

      case graph_step
      when Suspended
        build_suspended_result(token, joins, graph_step, &)
      when Advanced
        build_advanced_result(token, joins, graph_step)
      when Finished
        build_finished_result(joins, graph_step.state)
      else
        raise ValidationError, "Unsupported graph step result #{graph_step.class}"
      end
    end

    def advance_run(run:, resolved: nil, resolved_for: nil, resolve_request: nil, &)
      if resolved && resolved_for
        raise ArgumentError, "Runner#advance_run accepts either resolved: or resolved_for:, not both"
      end

      current_run = normalize_run(run)
      return current_run if current_run.finished?

      next_tokens, joins, final_state = advance_tokens(
        current_run,
        resolved_source: resolved || resolved_for,
        resolve_request: resolve_request,
        &
      )
      Run.new(
        status: run_status(final_state, next_tokens, joins),
        tokens: next_tokens,
        joins: joins,
        result: final_state
      )
    end

    private

    def normalize_run(run)
      return run if run.is_a?(Run)

      Run.new(
        status: run.fetch(:status).to_sym,
        tokens: run.fetch(:tokens, []),
        joins: run.fetch(:joins, {}),
        result: run[:result]
      )
    end

    def join_token?(token)
      token[:source_node] && @graph.join?(token.fetch(:node))
    end

    def build_join_result(join_result)
      case join_result
      when JoinParked
        Result.new(
          status: :parked,
          tokens: [],
          joins: join_result.joins,
          state: nil,
          requests: [],
          request_refs: {}
        )
      when JoinReleased
        Result.new(
          status: :released,
          tokens: [join_result.token],
          joins: join_result.joins,
          state: join_result.token.fetch(:state),
          requests: [],
          request_refs: {}
        )
      else
        raise ValidationError, "Unsupported join result #{join_result.class}"
      end
    end

    def build_suspended_result(token, joins, graph_step, &)
      awaits = token.fetch(:awaits, {}).dup
      request_refs = graph_step.requests.to_h do |request|
        key = request.key.to_sym
        [key, awaits[key] ||= bind_request(request, &)]
      end

      Result.new(
        status: :suspended,
        tokens: [
          {
            token_uid: token.fetch(:token_uid),
            node: graph_step.node,
            state: graph_step.state,
            fork_uid: token[:fork_uid],
            branch: token[:branch],
            source_node: token[:source_node],
            awaits: awaits
          }
        ],
        joins: joins,
        state: graph_step.state,
        requests: graph_step.requests,
        request_refs: request_refs
      )
    end

    def build_advanced_result(token, joins, graph_step)
      destinations = graph_step.destinations
      if destinations.size > 1
        fork_uid = fork_uid_for(token.fetch(:token_uid))
        tokens = destinations.map do |edge|
          suffix = edge.branch || edge.to
          {
            token_uid: "#{token.fetch(:token_uid)}.#{suffix}",
            node: edge.to,
            state: graph_step.state,
            fork_uid: fork_uid,
            branch: edge.branch,
            source_node: token.fetch(:node),
            awaits: {}
          }
        end

        return Result.new(
          status: :advanced,
          tokens: tokens,
          joins: joins,
          state: graph_step.state,
          requests: [],
          request_refs: {}
        )
      end

      edge = destinations.first
      return build_finished_result(joins, graph_step.state) if edge.to == FINISH

      Result.new(
        status: :advanced,
        tokens: [
          {
            token_uid: token.fetch(:token_uid),
            node: edge.to,
            state: graph_step.state,
            fork_uid: token[:fork_uid],
            branch: token[:branch],
            source_node: token.fetch(:node),
            awaits: {}
          }
        ],
        joins: joins,
        state: graph_step.state,
        requests: [],
        request_refs: {}
      )
    end

    def build_finished_result(joins, state)
      Result.new(
        status: :finished,
        tokens: [],
        joins: joins,
        state: state,
        requests: [],
        request_refs: {}
      )
    end

    def bind_request(request, &)
      return yield(request) if block_given?

      raise ArgumentError, "Runner#step requires a block to bind external IDs for new requests"
    end

    def advance_tokens(run, resolved_source:, resolve_request:, &)
      next_tokens = []
      joins = run.joins
      final_state = run.result

      run.tokens.each do |token|
        outcome = step(
          token: token,
          joins: joins,
          resolved: resolved_source&.call(token) || {},
          resolve_request: resolve_request,
          &
        )
        joins = outcome.joins
        next_tokens.concat(outcome.tokens)
        final_state = outcome.state if outcome.finished?
      end

      [next_tokens, joins, final_state]
    end

    def run_status(final_state, next_tokens, joins)
      final_state && next_tokens.empty? && joins.empty? ? :finished : :running
    end

    def fork_uid_for(token_uid) = "fork-#{token_uid}"
  end
end
