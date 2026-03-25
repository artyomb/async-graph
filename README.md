# AsyncGraph
Published docs: <https://artyomb.github.io/async-graph/>

AsyncGraph is a Ruby runtime for graph-style workflows that suspend on external work,
store jobs outside the graph, and resume on later passes. It supports:

- single-step graph execution
- runner helpers for opaque persisted run state and fan-out/join bookkeeping
- barrier joins such as `edge %i[left right], :merge`
- library-owned join processing for persisted branch tokens
- `await.call(...)` for one external job
- `await.all(...)` for multiple parallel jobs in one node
- graph validation before execution

## Installation

```bash
gem install async-graph
```

## Example

```ruby
require 'async-graph'

graph = AsyncGraph::Graph.new do
  node :fetch_user do |state, await|
    user = await.call("user", :fetch_user, user_id: state[:user_id])
    { user: user }
  end

  set_entry_point :fetch_user
  set_finish_point :fetch_user
end

step = graph.step(state: { user_id: 7 }, node: graph.entry)
request = step.requests.first

resumed = graph.step(
  state: step.state,
  node: step.node,
  resolved: { request.key => { id: 7, name: "Ada" } }
)

resumed.state
# => { user_id: 7, user: { id: 7, name: "Ada" } }
```

For persisted multi-pass execution, `AsyncGraph::Runner` can create and advance a run
snapshot while your application still owns persistence and external jobs.

## Demo

The repository includes two runnable examples in `examples/`:

- persisted multi-pass flow with external job persistence:

```bash
bash examples/run.sh
```

- self-contained runner loop with inline `:add` / `:subtract` request handling:

```bash
ruby examples/all_in_one_runner.rb
```

## Documentation

The repository also includes the Starlight source site in `docs-site/`.

```bash
cd docs-site
npm install
npm run dev
```
