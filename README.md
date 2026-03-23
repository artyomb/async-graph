# AsyncGraph
Published docs: <https://artyomb.github.io/async-graph/>

AsyncGraph is a Ruby runtime for graph-style workflows that suspend on external work,
store jobs outside the graph, and resume on later passes. It supports:

- single-step graph execution
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

## Demo

The repository includes a runnable example in `examples/`:

```bash
bash examples/run.sh
```

## Documentation

The repository also includes the Starlight source site in `docs-site/`.

```bash
cd docs-site
npm install
npm run dev
```
