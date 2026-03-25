---
title: Tokens and Joins
description: Advanced reference for custom runner integrations and join processing.
---

If you use `AsyncGraph::Runner#start_run` and `#advance_run`, persist the returned run
snapshot as-is and treat `run[:tokens]` and `run[:joins]` as runner-managed internal state.

Most applications do not need the details on this page. They matter only if you are
building a custom runner on top of `Runner#step` or `Graph#process_join`.

## Low-level token shape

`AsyncGraph::Runner` passes hashes shaped like this between steps:

```ruby
{
  token_uid: "graph-1.start",
  node: :merge,
  state: { user_id: 7 },
  fork_uid: "fork-graph-1.start",
  branch: :left,
  source_node: :left,
  awaits: { profile: "job-1" }
}
```

Field meanings:

- `token_uid`: stable identifier for the token instance
- `node`: current graph node to execute next
- `state`: accumulated graph state
- `fork_uid`: shared identifier for sibling branches created by fan-out; derived from the source token UID
- `branch`: branch label from the outgoing edge
- `source_node`: previous node used by join validation
- `awaits`: map from await key to external job identifier

If your persistence layer flattens tokens from many runs into shared tables, start each
run with a unique `token_uid` so the derived `fork_uid` stays unique too.

## Low-level join buckets

`graph.process_join(token:, joins:)` and `runner.step(token:, joins:, ...)` expect a
`joins` hash that your application persists between passes.

The runtime stores parked state under a key derived from `fork_uid` and the join node:

```ruby
:"#{fork_uid}:#{node}"
```

When all expected sources have arrived, the runtime removes the parked bucket and returns
an `AsyncGraph::JoinReleased` token that can continue through the graph.

## Prefer the run API

For normal usage:

- call `runner.start_run(...)`
- persist `run.to_h`
- call `runner.advance_run(run:, ...)`
- do not inspect `run[:tokens]` / `run[:joins]` or rebuild join buckets yourself

## Custom runner responsibilities

Your application should:

- save suspended tokens together with their `awaits` map
- rehydrate `resolved:` values before calling `runner.step(...)` or `graph.step(...)`
- call `process_join(...)` or use `AsyncGraph::Runner#step(...)` before entering a join node
- persist the updated `joins` hash returned by the runtime
