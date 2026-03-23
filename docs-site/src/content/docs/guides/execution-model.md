---
title: Execution Model
description: Understand how AsyncGraph executes one logical step at a time.
---

AsyncGraph advances one node at a time. The runtime does not schedule jobs or persist
state by itself. Instead, it returns enough information for your application to do both.

## Define nodes and edges

```ruby
graph = AsyncGraph::Graph.new do
  node :start do
    { seen: true }
  end

  node :done do
  end

  set_entry_point :start
  edge :start, :done
  set_finish_point :done
end
```

## Run one step

```ruby
step = graph.step(state: {}, node: graph.entry)
```

`graph.step(...)` executes the current node and returns one of three result objects:

| Result | Meaning |
| --- | --- |
| `AsyncGraph::Suspended` | The node called `await.call(...)` or `await.all(...)`. |
| `AsyncGraph::Advanced` | The node completed and produced next destinations. |
| `AsyncGraph::Finished` | The current node was `AsyncGraph::FINISH`. |

## What a node can return

Nodes control the next state and routing by what they return:

| Return value | Effect |
| --- | --- |
| `Hash` | Merged into state; normal outgoing edges are followed. |
| `AsyncGraph::Command` | Optional state update plus optional explicit `goto`. |
| `nil` or any other value | State is unchanged; normal outgoing edges are followed. |

## Normal edge resolution

If a node has one or more configured edges, `AsyncGraph::Advanced#destinations` returns
them in order. If a node has no outgoing edges, AsyncGraph implicitly routes it to
`AsyncGraph::FINISH`.

## External runner responsibilities

Your application owns:

- state persistence between passes
- external job dispatch and completion
- token persistence when fan-out creates multiple in-flight branches
- calling `process_join(...)` for barrier joins before re-entering the graph

See [Tokens and Joins](../reference/tokens-and-joins/) for the integration shape used by
the example runner.
