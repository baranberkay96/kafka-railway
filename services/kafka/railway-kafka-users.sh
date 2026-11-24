#!/bin/bash
# Background helper: once the broker is up, (re)apply the SCRAM credentials
# from the service variables over the container-local listener, so the
# variables stay the source of truth after the first start. Never prints secrets.
# Kafka rejects two mechanisms for one user in a single request, so each
# mechanism is its own call.
set -uo pipefail
log() { echo "railway-kafka-users: $*" >&2; }
user=$RAILWAY_KAFKA_USER pw=$RAILWAY_KAFKA_PASSWORD
unset RAILWAY_KAFKA_PASSWORD
out=/tmp/railway-kafka-users.out
for _ in $(seq 1 180); do
  (echo > /dev/tcp/127.0.0.1/9095) 2>/dev/null && break
  sleep 5
done
apply() { # mechanism
  KAFKA_HEAP_OPTS="-Xmx128m" /opt/kafka/bin/kafka-configs.sh --bootstrap-server 127.0.0.1:9095 --alter \
    --entity-type users --entity-name "$user" --add-config "$1=[password=$pw]" >"$out" 2>&1
}
for mechanism in SCRAM-SHA-512 SCRAM-SHA-256; do
  ok=""
  for _ in 1 2 3 4 5; do
    if apply "$mechanism"; then ok=1; break; fi
    tail -n 2 "$out" | sed -E 's/password=[^],]*/password=***/g' | cut -c1-300 >&2
    sleep 10
  done
  if [[ -z "$ok" ]]; then
    log "could not apply $mechanism credentials for '$user' (see above)"
    echo "user sync failed" > /tmp/railway-kafka-state
    rm -f "$out"; exit 0
  fi
done
rm -f "$out"
log "SCRAM-SHA-512/256 credentials for '$user' applied from KAFKA_SASL_PASSWORD"
echo "user '$user' ready" > /tmp/railway-kafka-state
