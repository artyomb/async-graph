# frozen_string_literal: true

require_relative "graph_validation"

module AsyncGraph
  FINISH = :__finish__
  DEFER = Object.new.freeze

  Request = Struct.new(:key, :kind, :payload, keyword_init: true)
  Edge = Struct.new(:to, :branch, keyword_init: true)
  AwaitSignal = Struct.new(:requests, keyword_init: true)

  class ValidationError < StandardError; end
  class JoinConflictError < StandardError; end

  class Command < Struct.new(:update, :goto, keyword_init: true)
    def self.goto(node) = new(goto: node)
    def self.update(delta) = new(update: delta)
    def self.update_and_goto(delta, node) = new(update: delta, goto: node)
  end

  class Advanced < Struct.new(:state, :destinations, keyword_init: true)
    def suspended? = false
    def finished? = false
  end

  class Suspended < Struct.new(:state, :node, :requests, keyword_init: true)
    def suspended? = true
    def finished? = false
  end

  class Finished < Struct.new(:state, keyword_init: true)
    def suspended? = false
    def finished? = true
  end

  class JoinParked < Struct.new(:joins, keyword_init: true)
    def parked? = true
    def released? = false
  end

  class JoinReleased < Struct.new(:token, :joins, keyword_init: true)
    def parked? = false
    def released? = true
  end

  # Interesting options for issuing multiple external jobs from one logical step:
  # 1. Model fan-out explicitly in the graph as a diamond.
  # 2. Use await.all(...) inside one node to queue a batch and suspend once.
  # 3. Use a two-phase API such as await.defer + await.resolve_all.
  class Await
    def initialize(resolved, resolve_request = nil)
      @resolved = resolved
      @resolve_request = resolve_request
    end

    def call(key, kind, payload = {})
      key = key.to_s
      return @resolved[key] if @resolved.key?(key)

      request = Request.new(key:, kind:, payload:)
      resolved = resolve(request)
      throw :await, AwaitSignal.new(requests: [request]) if resolved.equal?(DEFER)

      resolved
    end

    def all(definitions)
      normalized = definitions.to_h do |key, (kind, payload)|
        [key.to_s, [kind, payload || {}]]
      end

      resolved = {}
      missing = normalized.filter_map do |key, (kind, payload)|
        if @resolved.key?(key)
          resolved[key] = @resolved[key]
          next
        end

        request = Request.new(key:, kind:, payload:)
        value = resolve(request)
        if value.equal?(DEFER)
          request
        else
          resolved[key] = value
          nil
        end
      end

      throw :await, AwaitSignal.new(requests: missing) unless missing.empty?

      normalized.keys.to_h { |key| [key.to_sym, resolved[key]] }
    end

    def to_proc = method(:call).to_proc

    private

    def resolve(request)
      return DEFER unless @resolve_request

      @resolve_request.call(request.kind, request.payload)
    end
  end

  class Graph
    include GraphValidation

    attr_reader :entry

    def initialize(&block)
      @nodes = {}
      @edges = Hash.new { |hash, key| hash[key] = [] }
      @join_expects = {}
      @validated = false
      instance_eval(&block) if block
    end

    def node(name, &block)
      name = name.to_sym
      raise ValidationError, "Node #{name} requires a block" unless block
      raise ValidationError, "Node #{name} is already defined" if @nodes.key?(name)

      invalidate_validation!
      @nodes[name] = block
    end

    def edge(from, to, branch: nil)
      if from.is_a?(Array)
        sources = from.map(&:to_sym)
        validate_join_sources!(to, sources)

        target = to.to_sym
        raise ValidationError, "Join target #{target} is already defined" if @join_expects.key?(target)

        invalidate_validation!
        @join_expects[target] = sources
        sources.each { |item| edge(item, target, branch: item) }
      else
        invalidate_validation!
        add_edge(from.to_sym, Edge.new(to: to.to_sym, branch: branch&.to_sym))
      end
    end

    def set_entry_point(name)
      invalidate_validation!
      @entry = name.to_sym
    end

    def set_finish_point(name) = edge(name, FINISH)

    def step(state:, node:, resolved: {}, resolve_request: nil)
      validate!

      current = node.to_sym
      return Finished.new(state:) if current == FINISH

      validate_known_node!(current, context: "Step node")
      await = Await.new(resolved, resolve_request)
      result = catch(:await) { [:ok, call_node(@nodes[current], state, await)] }
      return Suspended.new(state:, node: current, requests: result.requests) if result.is_a?(AwaitSignal)

      Advanced.new(**advance(current, state, result.last))
    end

    def edges_from(node)
      validate!

      current = node.to_sym
      validate_known_node!(current, context: "Node")
      @edges[current].yield_self { |edges| edges.empty? ? [Edge.new(to: FINISH)] : edges }
    end

    def join?(node)
      validate!
      @join_expects.key?(node.to_sym)
    end

    def join_for(node)
      validate!
      @join_expects.fetch(node.to_sym) { raise ValidationError, "Node #{node} is not a join node" }
    end

    def process_join(token:, joins:)
      validate!

      current, expects, fork_uid, source = join_context(token)
      bucket_key = join_bucket_key(fork_uid, current)
      current_joins = joins.dup
      state = token.fetch(:state, {})
      states = next_join_states(current, source, current_joins[bucket_key], state)

      return park_join(current_joins, bucket_key, current, states) unless join_complete?(states, expects)

      current_joins.delete(bucket_key)
      release_join(current_joins, current, fork_uid, expects, states)
    end

    private

    def call_node(node, state, await)
      case node.arity
      when 0 then node.call
      when 1 then node.call(state, &await.to_proc)
      else node.call(state, await)
      end
    end

    def advance(node, state, result)
      case result
      when Hash
        { state: state.merge(result), destinations: edges_from(node) }
      when Command
        destinations =
          if result.goto
            target = result.goto.to_sym
            validate_destination!(target, context: "Goto target")
            [Edge.new(to: target)]
          else
            edges_from(node)
          end

        {
          state: state.merge(result.update || {}),
          destinations: destinations
        }
      else
        { state: state, destinations: edges_from(node) }
      end
    end

    def add_edge(from, edge)
      @edges[from] << edge unless @edges[from].any? { |existing| existing.to == edge.to && existing.branch == edge.branch }
    end

    def join_context(token)
      current = token.fetch(:node)&.to_sym
      validate_known_node!(current, context: "Join node")
      raise ValidationError, "Node #{current} is not a join node" unless join?(current)

      fork_uid = token.fetch(:fork_uid)
      raise ValidationError, "Join token for #{current} is missing fork_uid" if fork_uid.nil? || fork_uid.to_s.empty?

      source = token.fetch(:source_node)&.to_sym
      raise ValidationError, "Join token for #{current} is missing source_node" unless source

      expects = join_for(current)
      unless expects.include?(source)
        raise ValidationError, "Join token for #{current} arrived from unexpected source #{source}"
      end

      [current, expects, fork_uid, source]
    end

    def join_bucket_key(fork_uid, node)
      :"#{fork_uid}:#{node}"
    end

    def next_join_states(current, source, bucket, state)
      states = (bucket || {join_node: current, states: {}}).fetch(:states, {}).dup
      if states.key?(source) && states[source] != state
        raise JoinConflictError, "Join node #{current} received conflicting state for source #{source}"
      end

      states[source] = state
      states
    end

    def join_complete?(states, expects)
      (expects - states.keys).empty?
    end

    def park_join(current_joins, bucket_key, current, states)
      current_joins[bucket_key] = {
        join_node: current,
        states: states
      }
      JoinParked.new(joins: current_joins)
    end

    def release_join(current_joins, current, fork_uid, expects, states)
      JoinReleased.new(
        token: {
          token_uid: "#{fork_uid}.join",
          node: current,
          state: merge_join_states(states, expects, current),
          fork_uid: nil,
          branch: nil,
          source_node: nil,
          awaits: {}
        },
        joins: current_joins
      )
    end

    def merge_join_states(states, expects, current)
      expects.each_with_object({}) do |source, memo|
        state = states.fetch(source)
        conflicting = (memo.keys & state.keys).reject { |key| memo[key] == state[key] }
        unless conflicting.empty?
          raise JoinConflictError, "Join node #{current} has conflicting values for: #{conflicting.join(', ')}"
        end

        memo.merge!(state)
      end
    end
  end
end
