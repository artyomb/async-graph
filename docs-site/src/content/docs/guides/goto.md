---
title: Dynamic Goto
description: Override static graph edges at runtime with explicit routing commands.
---

Use `AsyncGraph::Command` when a node should decide the next destination dynamically.

## Route to another node

```ruby
node :router do |state|
  if state[:needs_review]
    AsyncGraph::Command.goto(:review)
  else
    AsyncGraph::Command.goto(:done)
  end
end
```

When a node returns `Command.goto(:target)`, AsyncGraph ignores the node's normal
outgoing edges for that step and emits a single destination pointing at `:target`.

## Update state and route in one return value

```ruby
node :router do |state|
  if state[:approved]
    AsyncGraph::Command.update_and_goto({ published: true }, :done)
  else
    AsyncGraph::Command.update({ review_requested: true })
  end
end
```

Available helpers:

- `AsyncGraph::Command.goto(node)`
- `AsyncGraph::Command.update(delta)`
- `AsyncGraph::Command.update_and_goto(delta, node)`

## Validation

Goto targets are validated when the command is applied. Routing to an unknown node raises
`AsyncGraph::ValidationError`.

## When to use goto

Good uses:

- router nodes
- conditional approval flows
- dynamic retries or fallback paths

Avoid using `goto` as a shortcut into a barrier join unless the token's `source_node`
still matches one of the join's declared source nodes. Join processing validates that
relationship.
