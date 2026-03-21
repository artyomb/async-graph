# frozen_string_literal: true

require "json"
require_relative "app_graph"

def job_for(jobs, job_uid)
  jobs.fetch("jobs", []).find { |job| job["job_uid"] == job_uid }
end

def resolved_for(token, jobs)
  token.fetch("awaits", {}).each_with_object({}) do |(key, job_uid), memo|
    job = job_for(jobs, job_uid)
    memo[key] = AsyncGraph.symbolize(job["result"]) if job && job["status"] == "done"
  end
end

def next_job_uid(jobs)
  "job-#{jobs.fetch("jobs", []).size + 1}"
end

def queue_job(jobs, request)
  job_uid = next_job_uid(jobs)
  jobs["jobs"] << AsyncGraph.stringify(
    job_uid: job_uid,
    kind: request.kind,
    payload: request.payload,
    status: :pending
  )
  job_uid
end

def spawn_tokens(graph_uid, token, state, destinations, next_tokens)
  if destinations.size > 1
    fork_uid = "fork-#{graph_uid}-#{token["token_uid"]}"

    destinations.each do |edge|
      next_tokens << AsyncGraph.stringify(
        token_uid: "#{token["token_uid"]}.#{edge.branch}",
        node: edge.to,
        state: state,
        fork_uid: fork_uid,
        branch: edge.branch,
        from_node: token["node"],
        awaits: {}
      )
    end

    return nil
  end

  edge = destinations.first
  return state if edge.to == AsyncGraph::FINISH

  next_tokens << AsyncGraph.stringify(
    token_uid: token["token_uid"],
    node: edge.to,
    state: state,
    fork_uid: token["fork_uid"],
    branch: token["branch"],
    from_node: token["node"],
    awaits: {}
  )

  nil
end

def process_join(graph_state, token, joins, next_tokens)
  expects = GRAPH.join_for(token["node"])
  bucket_key = "#{token["fork_uid"]}:#{token["node"]}"
  bucket = joins[bucket_key] || {"join_node" => token["node"], "states" => {}}
  bucket["states"][token["from_node"]] = token["state"]

  missing = expects.map(&:to_s) - bucket["states"].keys
  if missing.empty?
    joins.delete(bucket_key)
    merged_state = bucket["states"].values.reduce({}) do |memo, state|
      memo.merge(AsyncGraph.symbolize(state))
    end

    puts "#{graph_state["graph_uid"]}/#{token["token_uid"]} joined"
    next_tokens << AsyncGraph.stringify(
      token_uid: "#{token["fork_uid"]}.join",
      node: token["node"],
      state: merged_state,
      fork_uid: nil,
      branch: nil,
      from_node: nil,
      awaits: {}
    )
    return nil
  end

  joins[bucket_key] = bucket
  puts "#{graph_state["graph_uid"]}/#{token["token_uid"]} parked"
  nil
end

Dir.chdir(__dir__)

graph_states = JSON.parse(File.read("graph_states.json"))
jobs = JSON.parse(File.read("jobs.json"))

next_graph_states = graph_states.fetch("graphs", []).map do |graph_state|
  if graph_state["status"] == "finished"
    graph_state
  else
    next_tokens = []
    joins = graph_state["joins"] || {}
    final_state = graph_state["result"]

    graph_state.fetch("tokens", []).each do |token|
      if GRAPH.join?(token["node"]) && token["from_node"]
        process_join(graph_state, token, joins, next_tokens)
        next
      end

      waiting_jobs = token.fetch("awaits", {}).values
        .filter_map { |job_uid| job_for(jobs, job_uid) }
        .select { |job| job["status"] == "pending" }
      unless waiting_jobs.empty?
        puts "#{graph_state["graph_uid"]}/#{token["token_uid"]} waiting #{waiting_jobs.map { |job| job["job_uid"] }.join(",")}"
        next_tokens << token
        next
      end

      step = GRAPH.step(
        state: AsyncGraph.symbolize(token["state"]),
        node: token["node"],
        resolved: resolved_for(token, jobs)
      )

      case step
      when AsyncGraph::Suspended
        awaits = token.fetch("awaits", {}).dup
        job_uids = step.requests.map do |request|
          awaits[request.key] ||= queue_job(jobs, request)
        end
        puts "#{graph_state["graph_uid"]}/#{token["token_uid"]} suspended #{job_uids.join(",")}"
        next_tokens << AsyncGraph.stringify(
          token_uid: token["token_uid"],
          node: step.node,
          state: step.state,
          fork_uid: token["fork_uid"],
          branch: token["branch"],
          from_node: token["from_node"],
          awaits: awaits
        )
      when AsyncGraph::Advanced
        puts "#{graph_state["graph_uid"]}/#{token["token_uid"]} advanced"
        advanced_state = spawn_tokens(
          graph_state["graph_uid"],
          token,
          step.state,
          step.destinations,
          next_tokens
        )
        final_state = advanced_state if advanced_state
      when AsyncGraph::Finished
        final_state = step.state
      end
    end

    status = final_state && next_tokens.empty? && joins.empty? ? :finished : :running
    puts "#{graph_state["graph_uid"]} finished" if status == :finished

    {
      graph_uid: graph_state["graph_uid"],
      status: status,
      tokens: next_tokens,
      joins: joins,
      result: final_state
    }
  end
end

File.write(
  "graph_states.json",
  JSON.pretty_generate(AsyncGraph.stringify(graphs: next_graph_states)) + "\n"
)
File.write("jobs.json", JSON.pretty_generate(jobs) + "\n")
