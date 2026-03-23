---
title: Await External Work
description: Suspend a node until one or more external jobs have been resolved.
---

Use `await` when a node needs data that arrives later from outside the graph runtime.

## Request one external job

```ruby
node :fetch_user do |state, await|
  user = await.call("user", :fetch_user, user_id: state[:user_id])
  { user: user }
end
```

`await.call(key, kind, payload)` behaves like this:

1. If `resolved[key]` exists, it returns the resolved value immediately.
2. Otherwise it suspends the node and emits an `AsyncGraph::Request`.

## Request multiple jobs at once

```ruby
node :merge do |state, await|
  results = await.all(
    profile: [:fetch_profile, { user_id: state[:user_id] }],
    score: [:fetch_score, { user_id: state[:user_id] }]
  )

  {
    profile: results[:profile],
    score: results[:score]
  }
end
```

`await.all(...)` queues all missing requests in one suspension and returns a symbol-keyed
result hash after every key has been resolved.

## Resume a suspended node

Pass the saved node and state back into `graph.step(...)` together with a `resolved:`
hash:

```ruby
resumed = graph.step(
  state: suspended.state,
  node: suspended.node,
  resolved: {
    "profile" => { name: "Ada" },
    "score" => { score: 70 }
  }
)
```

## Key rules

- Request keys are normalized to strings internally.
- `await.all(...)` returns symbol keys such as `results[:profile]`.
- Your runner should persist the mapping from request key to external job identifier.
- Pending jobs stay outside the graph runtime by design.
