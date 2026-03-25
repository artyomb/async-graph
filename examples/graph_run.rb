# frozen_string_literal: true

require "json"
require_relative "app_graph"

def advance_graph_state!(graph_state, job_list, jobs_by_uid)
  graph_uid = graph_state.fetch(:graph_uid)
  next_run = RUNNER.advance_run(
    run: graph_state.fetch(:run),
    resolved_for: lambda do |token|
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
