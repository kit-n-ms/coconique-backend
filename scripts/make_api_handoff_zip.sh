#!/usr/bin/env bash
set -euo pipefail

OUTPUT="${1:-km_auth_starter_api_handoff.zip}"

zip -r "$OUTPUT" \
  app/controllers \
  app/models \
  app/mailers \
  app/views \
  app/lib \
  config/application.rb \
  config/routes.rb \
  config/initializers \
  config/environments \
  config/queue.yml \
  bin/jobs \
  db/migrate \
  db/queue_schema.rb \
  db/seeds.rb \
  lib/tasks \
  test \
  docs \
  Gemfile \
  Gemfile.lock \
  .env.example \
  README.md \
  -x "*.DS_Store" \
  -x "log/*" \
  -x "tmp/*" \
  -x "storage/*" \
  -x ".env" \
  -x ".env.local" \
  -x "config/master.key" \
  -x "config/credentials/*.key" \
  -x "config/database.yml"

echo "created: $OUTPUT"
