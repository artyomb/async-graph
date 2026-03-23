---
title: Barrier Joins
description: Fan out across multiple branches and merge them back safely.
---

AsyncGraph can model barrier joins where multiple branches must arrive before execution
continues.

## Declare a join

```ruby
graph = AsyncGraph::Graph.new do
  node :split do
  end

  node :left do
    { left_ready: true }
  end

  node :right do
    { right_ready: true }
  end

  node :merge do
  end

  set_entry_point :split
  edge :split, :left, branch: :left
  edge :split, :right, branch: :right
  edge %i[left right], :merge
end
```

`edge %i[left right], :merge` declares `:merge` as a barrier join and records the
expected source nodes in declaration order.

## Process join tokens outside the graph

The runtime does not own token persistence, so your application calls:

```ruby
join_result = graph.process_join(token: token, joins: joins)
```

This returns:

- `AsyncGraph::JoinParked` when not every expected branch has arrived yet
- `AsyncGraph::JoinReleased` when the join is complete and a merged token can re-enter the graph

## Token fields the join logic depends on

Join processing validates:

- `token[:node]`: the join node
- `token[:fork_uid]`: identifies the fork bucket
- `token[:from_node]`: the branch source that reached the join
- `token[:state]`: branch-local state to merge

## Conflict behavior

If two joined states disagree on the same key with different values, AsyncGraph raises
`AsyncGraph::JoinConflictError` instead of silently picking one branch.

## Important constraint

Joining is source-sensitive. A token arriving at a join must report a `from_node` that
matches one of the join's declared sources.
