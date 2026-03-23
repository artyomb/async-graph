---
title: Tokens and Joins
description: Reference for the token shape used by the example runner and join processing.
---

AsyncGraph does not persist execution state for you. The example runner in this repository
stores graph progress as tokens, jobs, and join buckets.

## Token shape

The example runner passes hashes shaped like this between steps:

```ruby
{
  token_uid: "graph-1.start",
  node: :merge,
  state: { user_id: 7 },
  fork_uid: "fork-graph-1-graph-1.start",
  branch: :left,
  from_node: :left,
  awaits: { profile: "job-1" }
}
```

Field meanings:

- `token_uid`: stable identifier for the token instance
- `node`: current graph node to execute next
- `state`: accumulated graph state
- `fork_uid`: shared identifier for sibling branches created by fan-out
- `branch`: branch label from the outgoing edge
- `from_node`: previous node used by join validation
- `awaits`: map from await key to external job identifier

## Join buckets

`graph.process_join(token:, joins:)` expects a `joins` hash that your application
persists between passes.

The runtime stores parked state under a key derived from `fork_uid` and the join node:

```ruby
:"#{fork_uid}:#{node}"
```

When all expected sources have arrived, the runtime removes the parked bucket and returns
an `AsyncGraph::JoinReleased` token that can continue through the graph.

## Runner responsibilities

Your runner should:

- save suspended tokens together with their `awaits` map
- rehydrate `resolved:` values before calling `graph.step(...)`
- call `process_join(...)` before entering a join node
- persist the updated `joins` hash returned by the runtime
