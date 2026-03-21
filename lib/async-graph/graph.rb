# frozen_string_literal: true

module AsyncGraph
  FINISH = :__finish__

  Request = Struct.new(:key, :kind, :payload, keyword_init: true)
  Edge = Struct.new(:to, :branch, keyword_init: true)
  AwaitSignal = Struct.new(:requests, keyword_init: true)

  def self.symbolize(object)
    case object
    when Array then object.map { |value| symbolize(value) }
    when Hash then object.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = symbolize(value) }
    else object
    end
  end

  def self.stringify(object)
    case object
    when Array then object.map { |value| stringify(value) }
    when Hash then object.each_with_object({}) { |(key, value), memo| memo[key.to_s] = stringify(value) }
    else object
    end
  end

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

  # Interesting options for issuing multiple external jobs from one logical step:
  # 1. Model fan-out explicitly in the graph as a diamond.
  # 2. Use await.all(...) inside one node to queue a batch and suspend once.
  # 3. Use a two-phase API such as await.defer + await.resolve_all.
  class Await
    def initialize(resolved)
      @resolved = resolved
    end

    def call(key, kind, payload = {})
      key = key.to_s
      return @resolved[key] if @resolved.key?(key)

      throw :await, AwaitSignal.new(requests: [Request.new(key:, kind:, payload:)])
    end

    def all(definitions)
      normalized = definitions.to_h do |key, (kind, payload)|
        [key.to_s, [kind, payload || {}]]
      end

      missing = normalized.filter_map do |key, (kind, payload)|
        next if @resolved.key?(key)

        Request.new(key:, kind:, payload:)
      end

      throw :await, AwaitSignal.new(requests: missing) unless missing.empty?

      normalized.keys.to_h { |key| [key.to_sym, @resolved[key]] }
    end

    def to_proc = method(:call).to_proc
  end

  class Graph
    attr_reader :entry

    def initialize(&block)
      @nodes = {}
      @edges = Hash.new { |hash, key| hash[key] = [] }
      @join_expects = {}
      instance_eval(&block) if block
    end

    def node(name, &block) = @nodes[name.to_sym] = block

    def edge(from, to, branch: nil)
      if from.is_a?(Array)
        @join_expects[to.to_sym] = from.map(&:to_sym)
        from.each { |item| edge(item, to, branch: item) }
      else
        @edges[from.to_sym] << Edge.new(to: to.to_sym, branch: branch&.to_sym)
      end
    end

    def set_entry_point(name) = @entry = name.to_sym
    def set_finish_point(name) = edge(name, FINISH)

    def step(state:, node:, resolved: {})
      current = node.to_sym
      return Finished.new(state:) if current == FINISH

      await = Await.new(resolved)
      result = catch(:await) { [:ok, call_node(@nodes.fetch(current), state, await)] }
      return Suspended.new(state:, node: current, requests: result.requests) if result.is_a?(AwaitSignal)

      Advanced.new(**advance(current, state, result.last))
    end

    def edges_from(node)
      @edges[node.to_sym].yield_self { |edges| edges.empty? ? [Edge.new(to: FINISH)] : edges }
    end

    def join?(node) = @join_expects.key?(node.to_sym)
    def join_for(node) = @join_expects.fetch(node.to_sym)

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
        {
          state: state.merge(result.update || {}),
          destinations: result.goto ? [Edge.new(to: result.goto.to_sym)] : edges_from(node)
        }
      else
        { state: state, destinations: edges_from(node) }
      end
    end
  end
end
