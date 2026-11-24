#!/bin/bash
# Apache Kafka on Railway: one KRaft node (broker + controller).
#
# Listeners
#   INTERNAL  [::]:9092  SASL_PLAINTEXT (SCRAM)  advertised as ${RAILWAY_PRIVATE_DOMAIN}:9092
#   EXTERNAL  [::]:9093  SASL_PLAINTEXT (SCRAM)  advertised as the TCP proxy domain:port
#   CONTROLLER 127.0.0.1:9094, LOCAL 127.0.0.1:9095 (PLAINTEXT, container only:
#   inter-broker traffic, healthz, user sync)
#
# Deploy-form values never stop the deploy (STANDARD 8.29): invalid values
# fall back to defaults; an invalid password locks the user with a random one
# and the log says how to fix it.
set -euo pipefail

log() { echo "railway-kafka: $*" >&2; }
random_secret() { head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
number() { # name default min max
  local value=${!1:-}
  if [[ -z "$value" ]]; then echo "$2"; return; fi
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < $3 || value > $4 )); then
    log "$1='$value' is not a number in $3-$4, using $2"; echo "$2"; return
  fi
  echo "$value"
}
bool() { # name default
  local value=${!1:-}; value=${value,,}
  case "$value" in true|false) echo "$value" ;; '') echo "$2" ;; *) log "$1='$value' is not true/false, using $2"; echo "$2" ;; esac
}

KAFKA_HOME=/opt/kafka
DATA="${RAILWAY_VOLUME_MOUNT_PATH:-/var/lib/kafka/data}"
LOG_DIR="$DATA/kafka-logs"
CONFIG=/etc/kafka/railway-server.properties

# --- credentials ---------------------------------------------------------------
USERNAME=${KAFKA_SASL_USERNAME:-kafka}
if [[ ! "$USERNAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
  log "KAFKA_SASL_USERNAME may only use letters, digits and . _ - (1-64), using 'kafka'"; USERNAME=kafka
fi
PASSWORD=${KAFKA_SASL_PASSWORD:-}
if [[ ! "$PASSWORD" =~ ^[A-Za-z0-9._~@%^*+-]{12,128}$ ]]; then
  log "WARNING: KAFKA_SASL_PASSWORD must be 12-128 characters of letters, digits and . _ ~ @ % ^ * + -"
  log "WARNING: user '$USERNAME' is LOCKED with a random password nobody knows; set KAFKA_SASL_PASSWORD and redeploy."
  PASSWORD=$(random_secret 40)
fi

# --- settings ------------------------------------------------------------------------
PARTITIONS=$(number KAFKA_NUM_PARTITIONS 3 1 1000)
RETENTION_HOURS=$(number KAFKA_LOG_RETENTION_HOURS 168 1 87600)
AUTO_CREATE=$(bool KAFKA_AUTO_CREATE_TOPICS true)
PRIVATE_HOST=${RAILWAY_PRIVATE_DOMAIN:-$(hostname)}
if [[ -n "${RAILWAY_TCP_PROXY_DOMAIN:-}" && "${RAILWAY_TCP_PROXY_PORT:-}" =~ ^[0-9]+$ ]]; then
  EXTERNAL="$RAILWAY_TCP_PROXY_DOMAIN:$RAILWAY_TCP_PROXY_PORT"
else
  log "no TCP proxy on this service: EXTERNAL listener advertised on the private network ($PRIVATE_HOST:9093)"
  EXTERNAL="$PRIVATE_HOST:9093"
fi

# Heap: 25 % of the memory limit (256-1024 MB); Kafka lives on the page cache.
if [[ -z "${KAFKA_HEAP_OPTS:-}" ]]; then
  heap=$(number KAFKA_HEAP_MB 0 128 65536)
  if (( heap == 0 )); then
    limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
    if [[ "$limit" =~ ^[0-9]+$ ]]; then heap=$(( limit / 1048576 / 4 )); else heap=512; fi
    (( heap < 256 )) && heap=256
    (( heap > 1024 )) && heap=1024
  fi
  export KAFKA_HEAP_OPTS="-Xms${heap}m -Xmx${heap}m"
fi

# --- volume -------------------------------------------------------------------------
mkdir -p "$LOG_DIR"
if [[ "$(stat -c %U "$LOG_DIR")" != appuser || "$(stat -c %U "$DATA")" != appuser ]]; then
  log "giving $DATA to appuser"
  chown -R appuser:root "$DATA"
fi

JAAS='org.apache.kafka.common.security.scram.ScramLoginModule required;'
cat > "$CONFIG" <<EOT
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@127.0.0.1:9094
controller.listener.names=CONTROLLER
inter.broker.listener.name=LOCAL
listeners=INTERNAL://[::]:9092,EXTERNAL://[::]:9093,CONTROLLER://127.0.0.1:9094,LOCAL://127.0.0.1:9095
advertised.listeners=INTERNAL://${PRIVATE_HOST}:9092,EXTERNAL://${EXTERNAL},LOCAL://127.0.0.1:9095
listener.security.protocol.map=INTERNAL:SASL_PLAINTEXT,EXTERNAL:SASL_PLAINTEXT,CONTROLLER:PLAINTEXT,LOCAL:PLAINTEXT
sasl.enabled.mechanisms=SCRAM-SHA-512,SCRAM-SHA-256
listener.name.internal.scram-sha-512.sasl.jaas.config=${JAAS}
listener.name.internal.scram-sha-256.sasl.jaas.config=${JAAS}
listener.name.external.scram-sha-512.sasl.jaas.config=${JAAS}
listener.name.external.scram-sha-256.sasl.jaas.config=${JAAS}
log.dirs=${LOG_DIR}
num.partitions=${PARTITIONS}
default.replication.factor=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
share.coordinator.state.topic.replication.factor=1
share.coordinator.state.topic.min.isr=1
auto.create.topics.enable=${AUTO_CREATE}
log.retention.hours=${RETENTION_HOURS}
group.initial.rebalance.delay.ms=0
EOT
chown appuser:root "$CONFIG"

# --- first start: format the KRaft storage with the SCRAM user ------------------------------
if [[ ! -f "$LOG_DIR/meta.properties" ]]; then
  cluster_id=$(su-exec appuser "$KAFKA_HOME/bin/kafka-storage.sh" random-uuid)
  log "formatting new KRaft storage (cluster id $cluster_id)"
  KAFKA_HEAP_OPTS="-Xmx256m" su-exec appuser "$KAFKA_HOME/bin/kafka-storage.sh" format \
    -t "$cluster_id" -c "$CONFIG" --ignore-formatted \
    --add-scram "SCRAM-SHA-512=[name=$USERNAME,password=$PASSWORD]" \
    --add-scram "SCRAM-SHA-256=[name=$USERNAME,password=$PASSWORD]" >/dev/null
fi

# --- helpers ------------------------------------------------------------------------------
echo "starting" > /tmp/railway-kafka-state
chmod 0666 /tmp/railway-kafka-state
su-exec appuser /usr/local/bin/railway-healthz &
RAILWAY_KAFKA_USER="$USERNAME" RAILWAY_KAFKA_PASSWORD="$PASSWORD" su-exec appuser /usr/local/bin/railway-kafka-users &
unset PASSWORD KAFKA_SASL_PASSWORD

log "starting Kafka (KRaft), user '$USERNAME', private $PRIVATE_HOST:9092, external $EXTERNAL, heap: $KAFKA_HEAP_OPTS"
cd "$KAFKA_HOME"
exec su-exec appuser "$KAFKA_HOME/bin/kafka-server-start.sh" "$CONFIG"
