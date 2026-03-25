---
title: Runtime API
description: Reference for the main AsyncGraph classes and methods.
---

## Core classes

### `AsyncGraph::Graph`

Builds and executes the workflow graph.

Methods:

- `node(name, &block)`: define a node block under a symbolic name.
- `edge(from, to, branch: nil)`: add a normal edge or a barrier join edge.
- `set_entry_point(name)`: mark the first node.
- `set_finish_point(name)`: route a node to `AsyncGraph::FINISH`.
- `step(state:, node:, resolved: {})`: execute one logical step.
- `edges_from(node)`: inspect configured destinations.
- `join?(node)`: check whether a node is a barrier join.
- `join_for(node)`: return the source nodes expected by a join.
- `process_join(token:, joins:)`: park or release join tokens for custom runners.
- `validate!`: validate the graph before execution-facing operations.

### `AsyncGraph::Await`

Used inside node blocks to suspend on external work.

Methods:

- `call(key, kind, payload = {})`
- `all(definitions)`

### `AsyncGraph::Command`

Explicit control signal returned from a node.

Helpers:

- `goto(node)`
- `update(delta)`
- `update_and_goto(delta, node)`

### `AsyncGraph::Runner`

Optional helper for applications that want the gem to manage persisted execution state
between passes while still keeping persistence and job execution outside the gem.

Methods:

- `start_run(state:, token_uid: "t1")`: build a persisted run snapshot with runner-managed `tokens` and `joins`.
- `advance_run(run:, resolved_for: nil) { |request| ... }`: advance one persisted run by one pass.
- `start(state:, token_uid: "t1")`: build an entry token for persisted execution.
- `step(token:, joins:, resolved: {}) { |request| ... }`: low-level token step for custom runners.

## Result objects

### `AsyncGraph::Suspended`

Fields:

- `state`
- `node`
- `requests`

### `AsyncGraph::Advanced`

Fields:

- `state`
- `destinations`

### `AsyncGraph::Finished`

Fields:

- `state`

### `AsyncGraph::Runner::Result`

Fields:

- `status`
- `tokens`
- `joins`
- `state`
- `requests`
- `request_refs`

### `AsyncGraph::Runner::Run`

Fields:

- `status`
- `tokens`
- `joins`
- `result`

### `AsyncGraph::JoinParked`

Fields:

- `joins`

### `AsyncGraph::JoinReleased`

Fields:

- `token`
- `joins`

## Errors

- `AsyncGraph::ValidationError`
- `AsyncGraph::JoinConflictError`

## Constants and structs

- `AsyncGraph::FINISH`
- `AsyncGraph::Request`
- `AsyncGraph::Edge`
- `AsyncGraph::AwaitSignal`
