# TEMPLATE: Apache Kafka 4.4 with Kafbat UI

Composer spec. `template.json` is the machine-readable copy.

## Services

| Field | Kafka | Kafka UI |
|---|---|---|
| Source | repo `baranberkay96/kafka-railway`, root `/services/kafka` | image `kafbat/kafka-ui:v1.5.1@sha256:c0585fdf…` (2026-11-20) |
| Base | `apache/kafka:4.4.0@sha256:833b867a…` (2026-10-22, 240 MB compressed) + python3, su-exec | - |
| Network | private 9092; TCP proxy → 9093; healthz 8080 (no domain) | public domain, 8080 |
| Healthcheck | `/healthz` (200 when the broker accepts connections), 600 s | `/actuator/health`, 600 s |
| Restart | ALWAYS | ALWAYS |
| Volume | `/var/lib/kafka/data` (logs in `kafka-logs/`) | - |

Kafka variables: `KAFKA_SASL_USERNAME` kafka, `KAFKA_SASL_PASSWORD` (secret 32), `KAFKA_NUM_PARTITIONS` 3, `KAFKA_AUTO_CREATE_TOPICS` true, `KAFKA_LOG_RETENTION_HOURS` 168, `KAFKA_HEAP_MB` empty, `PORT` 8080, `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_PUBLIC_BOOTSTRAP_SERVERS`, `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` 60.
Kafka UI variables: `AUTH_TYPE` LOGIN_FORM, `SPRING_SECURITY_USER_NAME` admin, `SPRING_SECURITY_USER_PASSWORD` (secret 24), `KAFKA_CLUSTERS_0_*` (bootstrap, SASL_PLAINTEXT, SCRAM-SHA-512, JAAS from Kafka's variables), `DYNAMIC_CONFIG_ENABLED` false, `SERVER_PORT`/`PORT` 8080. No required inputs.

## Design

- KRaft combined node, static quorum `1@127.0.0.1:9094`. Listeners INTERNAL `[::]:9092` and EXTERNAL `[::]:9093` (SASL_PLAINTEXT, SCRAM-SHA-512/256, dual-stack, STANDARD 8.14), CONTROLLER and LOCAL on loopback; `inter.broker.listener.name=LOCAL` (no self-DNS, 8.13).
- Advertised: INTERNAL → `RAILWAY_PRIVATE_DOMAIN:9092`, EXTERNAL → `RAILWAY_TCP_PROXY_DOMAIN:RAILWAY_TCP_PROXY_PORT` (private host if no proxy).
- First start: `kafka-storage format --add-scram` (user exists before the port opens, 8.37). Every start: `railway-kafka-users` re-applies the SCRAM credentials over LOCAL (variables stay authoritative).
- Heap 25% of the cgroup limit (256-1024 MB); `su-exec appuser`; volume chowned on first start; RF 1 for internal topics.
- 8.29: invalid user → `kafka`, invalid password → random (locked) with log, invalid numbers/booleans → defaults.

## Improvements over market templates

- The three market Kafka templates use `apache/kafka:latest` or a ZooKeeper-based build, expose PLAINTEXT (no authentication) on their TCP proxies and have no healthcheck or UI. This template pins 4.4.0 by digest and uses KRaft, SCRAM on every external listener, a dual-stack private listener, a real healthcheck and a login-protected UI.

## Resources

| Service | Idle RAM | Typical RAM | CPU |
|---|---|---|---|
| Kafka | 0.8 GB measured (1 GB heap); 0.38 GB under a 1 GB limit | heap + page cache | low idle |
| Kafka UI | 0.45 GB measured; 0.25 GB under a 1 GB limit | 300-500 MB | low |

Estimated cost: ≈$5-12/month idle-to-light + volume. Minimum plan: Trial for light use.

## Verification checklist

- Kafka `/healthz` passes; UI `/actuator/health` 200; UI pages need login.
- Produce/consume through the TCP proxy with SCRAM-SHA-512; wrong password rejected.
- UI lists the cluster, topics and messages.
- Redeploy: topics and messages survive; changed password applies.
- `KAFKA_SASL_PASSWORD=short` → deploy SUCCESS, user locked, warning.

## Open questions

- EXTERNAL listener is SASL without TLS (Railway's TCP proxy passes raw TCP); a TLS listener with a self-signed certificate could be added later.
