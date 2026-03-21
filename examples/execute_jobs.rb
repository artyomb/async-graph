# frozen_string_literal: true

require "json"

Dir.chdir(__dir__)

jobs = JSON.parse(File.read("jobs.json"))

jobs.fetch("jobs", []).each do |job|
  next unless job["status"] == "pending"

  job["result"] =
    case job["kind"]
    when "fetch_profile"
      user_id = job.dig("payload", "user_id")
      {"id" => user_id, "name" => "Ada-#{user_id}"}
    when "fetch_score"
      user_id = job.dig("payload", "user_id")
      {"score" => user_id * 10}
    end

  next unless job["result"]

  job["status"] = "done"
  puts "done #{job["job_uid"]} #{job["kind"]}"
end

File.write("jobs.json", JSON.pretty_generate(jobs) + "\n")
