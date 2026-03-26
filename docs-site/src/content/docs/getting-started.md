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

If you want runnable runner examples, the repository includes two variants:

- [`examples/all_in_one_inline_runner.rb`](https://github.com/artyomb/async-graph/blob/main/examples/all_in_one_inline_runner.rb):
  resolves simple `:add` / `:subtract` operations inline through `resolve_request:`
- [`examples/all_in_one_jobs_runner.rb`](https://github.com/artyomb/async-graph/blob/main/examples/all_in_one_jobs_runner.rb):
  uses normal suspension, binds requests to in-memory job IDs, and resumes in the same process

Commands:

```bash
ruby examples/all_in_one_inline_runner.rb
ruby examples/all_in_one_jobs_runner.rb
```

The full code and a detailed explanation of both variants, plus the persisted multi-pass
demo in `examples/run.sh`, are documented in [Example Walkthroughs](./guides/examples/).

## Read next

- [Example Walkthroughs](./guides/examples/)
- [Execution Model](./guides/execution-model/)
- [Await External Work](./guides/await/)
- [Barrier Joins](./guides/joins/)
- [Dynamic Goto](./guides/goto/)
