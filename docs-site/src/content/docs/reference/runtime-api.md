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
- `process_join(token:, joins:)`: park or release join tokens.
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
