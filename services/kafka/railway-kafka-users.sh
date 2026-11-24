#!/bin/bash
# Background helper: once the broker is up, (re)apply the SCRAM credentials
# from the service variables over the container-local listener, so the
# variables stay the source of truth after the first start. Never prints secrets.
set -uo pipefail
log() { echo "railway-kafka-users: $*" >&2; }
user=$RAILWAY_KAFKA_USER pw=$RAILWAY_KAFKA_PASSWORD
unset RAILWAY_KAFKA_PASSWORD
for _ in $(seq 1 180); do
  (echo > /dev/tcp/127.0.0.1/9095) 2>/dev/null && break
  sleep 5
done
for attempt in 1 2 3 4 5; do
  if KAFKA_HEAP_OPTS="-Xmx128m" /opt/kafka/bin/kafka-configs.sh --bootstrap-server 127.0.0.1:9095 --alter \
      --entity-type users --entity-name "$user" \
      --add-config "SCRAM-SHA-512=[password=$pw],SCRAM-SHA-256=[password=$pw]" >/dev/null 2>&1; then
    log "SCRAM credentials for '$user' applied"
    echo "user '$user' ready" > /tmp/railway-kafka-state
    exit 0
  fi
  sleep 10
done
log "could not apply SCRAM credentials (see broker log)"
echo "user sync failed" > /tmp/railway-kafka-state
