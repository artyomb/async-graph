---
title: Example Walkthroughs
description: Full runnable examples for inline resolution, in-memory jobs, and persisted multi-pass execution.
---

This page expands the runnable examples from `examples/` and explains what each one is
demonstrating, why the code is structured that way, and when you would pick one pattern
over another.

## Which example should you start with?

- Use `all_in_one_inline_runner.rb` when some request kinds can be resolved immediately
  inside the current process and you want to avoid suspension entirely for those cases.
- Use `all_in_one_jobs_runner.rb` when you want to keep the normal suspend/bind/resume
  shape, but still demonstrate it without a real external queue.
- Use the persisted multi-pass demo when you want to see the intended production
  integration shape: persisted run snapshots, persisted jobs, worker completion, and
  later resumption.

## Inline Runner Example

Source: [`examples/all_in_one_inline_runner.rb`](https://github.com/artyomb/async-graph/blob/main/examples/all_in_one_inline_runner.rb)

Run it with:

```bash
ruby examples/all_in_one_inline_runner.rb
```

Full code:

```ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/async-graph"

runner = AsyncGraph::Runner.new(
  AsyncGraph::Graph.new do
    node :calculate do |state, await|
      results = await.all(
        added: [:add, {left: state[:left], right: state[:right]}],
        subtracted: [:subtract, {left: state[:total], right: state[:discount]}]
      )

      {
        added: results[:added],
        subtracted: results[:subtracted],
        answer: results[:added] - results[:subtracted]
      }
    end

    set_entry_point :calculate
    set_finish_point :calculate
  end
)

run = runner.start_run state: {left: 7, right: 5, total: 20, discount: 3}

until run.finished?
  run = runner.advance_run(
    run: run,
    resolve_request: lambda do |kind, payload|
      case kind
      when :add then payload[:left] + payload[:right]
      when :subtract then payload[:left] - payload[:right]
      else AsyncGraph::DEFER
      end
    end
  )
end

puts JSON.pretty_generate(run.result)
```

What this example shows:

1. The node still uses normal `await.all(...)` calls. It does not know or care whether
   a request will resolve inline or suspend.
2. `resolve_request:` on `runner.advance_run(...)` decides whether a request kind can be
   handled immediately.
3. Returning a value means “use this now”.
4. Returning `AsyncGraph::DEFER` means “this request is still external, suspend as usual”.
5. Because both `:add` and `:subtract` resolve inline here, the run finishes without
   ever exposing suspended requests to caller code.

Why this pattern is useful:

- It keeps node code declarative.
- It lets the runtime decide suspension based on current environment or request kind.
- It is a good fit for local adapters, cache hits, pure calculations, or “fast path”
  request kinds that should not leave the process.

Important detail:

Even in the inline case, the graph contract is still written in terms of requests.
`await.call(...)` and `await.all(...)` remain the way nodes ask for outside data. The
only difference is that `resolve_request:` gives the runtime a chance to satisfy some of
those requests before a `Suspended` result is produced.

## In-Memory Jobs Runner Example

Source: [`examples/all_in_one_jobs_runner.rb`](https://github.com/artyomb/async-graph/blob/main/examples/all_in_one_jobs_runner.rb)

Run it with:

```bash
ruby examples/all_in_one_jobs_runner.rb
```

Full code:

```ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/async-graph"

runner = AsyncGraph::Runner.new(
  AsyncGraph::Graph.new do
    node :calculate do |state, await|
      results = await.all(
        added: [:add, {left: state[:left], right: state[:right]}],
        subtracted: [:subtract, {left: state[:total], right: state[:discount]}]
      )

      {
        added: results[:added],
        subtracted: results[:subtracted],
        answer: results[:added] - results[:subtracted]
      }
    end

    set_entry_point :calculate
    set_finish_point :calculate
  end
)

results = {}
run = runner.start_run state: {left: 7, right: 5, total: 20, discount: 3}

until run.finished?
  run = runner.advance_run(
    run: run,
    resolved: lambda do |token|
      token[:awaits].each_with_object({}) do |(key, request_id), memo|
        memo[key.to_s] = results[request_id] if results.key?(request_id)
      end
    end
  ) do |request|
    results[request.key] =
      case request.kind
      when :add then request.payload[:left] + request.payload[:right]
      when :subtract then request.payload[:left] - request.payload[:right]
      end

    request.key
  end
end

puts JSON.pretty_generate(run.result)
```

What this example shows:

1. The run still suspends when the node hits `await.all(...)`.
2. The block given to `advance_run(...)` is called only for newly deferred requests.
3. The block binds each request to an external reference. In this example, the external
   reference is just `request.key`, but in a real system it would usually be a job ID or
   queue record ID.
4. The `resolved:` lambda reconstructs the `resolved` payload map expected by the graph
   from the runner-managed `token[:awaits]` state.
5. On the next pass, `await.all(...)` sees that both request keys are now resolved and
   the node continues normally.

Why this pattern is useful:

- It matches the real suspend/resume lifecycle.
- It shows exactly where request binding and later resolution happen.
- It keeps persistence concerns outside the graph runtime while still letting the runner
  manage tokens and joins.

If you are integrating AsyncGraph into an application with queues, tables, or job
records, this is the better mental model to start from.

## Persisted Multi-Pass Demo

This example spans several files because it models the full shape of an application that
stores run state between passes and stores jobs separately from the graph.

Run it with:

```bash
bash examples/run.sh
```

The demo is split into four files:

- `app_graph.rb`: graph definition and runner construction
- `reset.rb`: seed persisted graph state and empty jobs
- `graph_run.rb`: advance each saved run by one pass and queue new jobs
- `execute_jobs.rb`: simulate an external worker that finishes pending jobs

### `app_graph.rb`

Source: [`examples/app_graph.rb`](https://github.com/artyomb/async-graph/blob/main/examples/app_graph.rb)

```ruby
# frozen_string_literal: true

require_relative "../lib/async-graph"

GRAPH = AsyncGraph::Graph.new do
  node :split do
  end

  node :left do
    { left_ready: true }
  end

  node :right do
    { right_ready: true }
  end

  node :merge do |state, await|
    results = await.all(
      profile: [:fetch_profile, {user_id: state[:user_id]}],
      score: [:fetch_score, {user_id: state[:user_id]}]
    )

    {
      left: results[:profile],
      right: results[:score],
      message: "#{results[:profile][:name]} score=#{results[:score][:score]}"
    }
  end

  set_entry_point :split
  edge :split, :left, branch: :left
  edge :split, :right, branch: :right
  edge %i[left right], :merge
  set_finish_point :merge
end

RUNNER = AsyncGraph::Runner.new(GRAPH)
```

Why it matters:

- `:split` fans out into `:left` and `:right`.
- `edge %i[left right], :merge` declares a barrier join, so the runtime will not
  continue into `:merge` until both branches arrive.
- The `:merge` node uses `await.all(...)` to request both `profile` and `score` in one
  suspension point.

### `reset.rb`

Source: [`examples/reset.rb`](https://github.com/artyomb/async-graph/blob/main/examples/reset.rb)

```ruby
# frozen_string_literal: true

require "json"
require_relative "app_graph"

Dir.chdir(__dir__)

File.write(
  "graph_states.json",
  JSON.pretty_generate(
    graphs: [
      {
        graph_uid: "graph-1",
        run: RUNNER.start_run(state: {user_id: 7}).to_h
      },
      {
        graph_uid: "graph-2",
        run: RUNNER.start_run(state: {user_id: 8}).to_h
      }
    ]
  ) + "\n"
)
File.write("jobs.json", JSON.pretty_generate(jobs: []) + "\n")

puts "reset"
```

Why it matters:

- It seeds two independent persisted runs.
- Each run starts from a `start_run(...).to_h` snapshot, which is exactly the shape you
  would persist in a database or document store.

### `graph_run.rb`

Source: [`examples/graph_run.rb`](https://github.com/artyomb/async-graph/blob/main/examples/graph_run.rb)

```ruby
# frozen_string_literal: true

require "json"
require_relative "app_graph"

def advance_graph_state!(graph_state, job_list, jobs_by_uid)
  graph_uid = graph_state.fetch(:graph_uid)
  next_run = RUNNER.advance_run(
    run: graph_state.fetch(:run),
    resolved: lambda do |token|
      token.fetch(:awaits, {}).each_with_object({}) do |(key, job_uid), memo|
        job = jobs_by_uid[job_uid]
        memo[key.to_s] = job[:result] if job&.[](:status) == "done"
      end
    end
  ) do |request|
    job_uid = "job-#{job_list.size + 1}"
    job = jobs_by_uid[job_uid] = {
      job_uid: job_uid,
      kind: request.kind.to_s,
      payload: request.payload,
      status: "pending"
    }
    job_list << job
    job_uid
  end

  puts "#{graph_uid} finished" if next_run.finished?
  graph_state[:run] = next_run.to_h
end

Dir.chdir(__dir__)

graph_states = JSON.parse(File.read("graph_states.json"), symbolize_names: true)
jobs = JSON.parse(File.read("jobs.json"), symbolize_names: true)
job_list = jobs.fetch(:jobs)
jobs_by_uid = job_list.to_h { |job| [job[:job_uid], job] }

graph_states.fetch(:graphs, [])
  .reject { it.dig(:run, :status) == "finished" }
  .each { advance_graph_state!(it, job_list, jobs_by_uid) }

File.write("graph_states.json", JSON.pretty_generate(graph_states) + "\n")
File.write("jobs.json", JSON.pretty_generate(jobs) + "\n")
```

Why it matters:

- `resolved:` translates completed job records back into the string-keyed payload map
  expected by the runtime.
- The block allocates new job IDs only for newly deferred requests.
- `graph_state[:run] = next_run.to_h` persists the updated run snapshot after every pass.
- The script can be rerun safely because it always starts from persisted `graph_states`
  and `jobs` JSON.

### `execute_jobs.rb`

Source: [`examples/execute_jobs.rb`](https://github.com/artyomb/async-graph/blob/main/examples/execute_jobs.rb)

```ruby
# frozen_string_literal: true

require "json"

Dir.chdir(__dir__)

jobs = JSON.parse(File.read("jobs.json"), symbolize_names: true)

jobs.fetch(:jobs, []).each do |job|
  next unless job[:status] == "pending"

  job[:result] =
    case job[:kind]
    when "fetch_profile"
      user_id = job.dig(:payload, :user_id)
      {id: user_id, name: "Ada-#{user_id}"}
    when "fetch_score"
      user_id = job.dig(:payload, :user_id)
      {score: user_id * 10}
    end

  next unless job[:result]

  job[:status] = "done"
  puts "done #{job[:job_uid]} #{job[:kind]}"
end

File.write("jobs.json", JSON.pretty_generate(jobs) + "\n")
```

Why it matters:

- It stands in for a real worker process.
- It does not know anything about graph structure, joins, or runner state.
- Its only contract is: read pending jobs, write completed results.

## What the persisted demo teaches

1. Graph execution state and external job state are separate.
2. The runner owns token and join bookkeeping, but not persistence.
3. Request keys stay inside the graph contract, while job IDs belong to your application.
4. Resumption is just another call to `advance_run(...)` with a new `resolved:` view of
   the world.

## What to read next

- [Getting Started](/async-graph/getting-started/)
- [Await External Work](/async-graph/guides/await/)
- [Barrier Joins](/async-graph/guides/joins/)
- [Tokens and Joins](/async-graph/reference/tokens-and-joins/)
