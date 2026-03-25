#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

for file in app_graph.rb reset.rb graph_run.rb execute_jobs.rb all_in_one_runner.rb; do
  ruby -c "$file"
done

printf '\n== reset ==\n'
ruby reset.rb
cat graph_states.json
cat jobs.json

printf '\n== graph run 1 ==\n'
ruby graph_run.rb
cat graph_states.json
cat jobs.json

printf '\n== graph run 2 ==\n'
ruby graph_run.rb
cat graph_states.json
cat jobs.json

printf '\n== graph run 3 ==\n'
ruby graph_run.rb
cat graph_states.json
cat jobs.json

printf '\n== graph run 4 ==\n'
ruby graph_run.rb
cat graph_states.json
cat jobs.json

printf '\n== execute jobs ==\n'
ruby execute_jobs.rb
cat jobs.json

printf '\n== graph run 5 ==\n'
ruby graph_run.rb
cat graph_states.json
cat jobs.json

printf '\n== all-in-one runner ==\n'
ruby all_in_one_runner.rb
