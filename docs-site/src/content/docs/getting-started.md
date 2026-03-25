---
title: Getting Started
description: Install AsyncGraph and run a minimal suspend/resume workflow.
---

AsyncGraph is a small Ruby runtime for graph-style workflows that suspend on external
work, store jobs outside the graph, and resume on later passes.

## Install the gem

```bash
gem install async-graph
```

## Build a minimal graph

```ruby
require "async-graph"

graph = AsyncGraph::Graph.new do
  node :fetch_user do |state, await|
    user = await.call("user", :fetch_user, user_id: state[:user_id])
    { user: user }
  end

  set_entry_point :fetch_user
  set_finish_point :fetch_user
end
```

On the first pass, the node suspends because the `"user"` request is unresolved:

```ruby
step = graph.step(state: { user_id: 7 }, node: graph.entry)

step.class
# => AsyncGraph::Suspended

step.requests.first.key
# => "user"
```

Once your worker finishes the external job, call `step` again with the resolved
payload:

```ruby
resumed = graph.step(
  state: step.state,
  node: step.node,
  resolved: { "user" => { id: 7, name: "Ada" } }
)

resumed.class
# => AsyncGraph::Advanced

resumed.state
# => { user_id: 7, user: { id: 7, name: "Ada" } }
```

## What the runtime returns

- `AsyncGraph::Suspended`: the current node requested external work.
- `AsyncGraph::Advanced`: the node completed and emitted one or more next destinations.
- `AsyncGraph::Finished`: execution reached `AsyncGraph::FINISH`.

## Runner example

If you want one self-contained example of the runner API, the repository includes
[`examples/all_in_one_runner.rb`](https://github.com/artyomb/async-graph/blob/main/examples/all_in_one_runner.rb).
It keeps request results in memory and resolves simple `:add` / `:subtract` operations
inline:

```bash
ruby examples/all_in_one_runner.rb
```

Full example code:

```ruby
require "json"
require "async-graph"

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
run = runner.start_run(state: {left: 7, right: 5, total: 20, discount: 3})

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
```

This is still a suspend/resume flow. The difference is only that the example resolves
requests immediately inside the same process instead of persisting them to an external
job system.

## Read next

- [Execution Model](./guides/execution-model/)
- [Await External Work](./guides/await/)
- [Barrier Joins](./guides/joins/)
- [Dynamic Goto](./guides/goto/)
