# Deploy and Host Apache Kafka with Railway

Apache Kafka is the open-source distributed event streaming platform used for data pipelines, event-driven microservices, streaming analytics and log aggregation. This template runs Kafka 4.4 as a single KRaft node (no ZooKeeper) with SASL/SCRAM authentication, reachable privately and through a TCP proxy, plus Kafbat UI behind a login.

## About Hosting Apache Kafka

Kafka needs a persistent log directory, listeners whose advertised addresses match how each client reaches the broker, and authentication before any port faces the internet. This community template builds the official `apache/kafka` image (pinned by digest) with a start script that formats KRaft storage on first boot, advertises the Railway private domain to services inside the project and the TCP proxy address to clients outside, listens dual-stack, sizes the JVM heap from the service's memory limit, and re-applies the SCRAM user from the service variables on every start. A private `/healthz` gives Railway a real readiness signal. Kafbat UI connects over the private network and is protected by its login form.

## Common Use Cases

- Event-driven microservices and asynchronous job pipelines
- Change data capture and data integration (Kafka Connect, Debezium) from your databases
- Collecting logs, metrics and clickstream events before they land in a warehouse
- Development and staging brokers that match your production Kafka API

## Dependencies for Apache Kafka Hosting

- Apache Kafka 4.4.0 (official image) with a Railway volume for its log directory
- Kafbat UI 1.5.1 (official image), Apache-2.0, web UI for topics, messages and consumer groups

### Deployment Dependencies

- [Apache Kafka documentation](https://kafka.apache.org/documentation/)
- [KRaft operations](https://kafka.apache.org/documentation/#kraft)
- [SASL/SCRAM authentication](https://kafka.apache.org/documentation/#security_sasl_scram)
- [Kafbat UI](https://github.com/kafbat/kafka-ui)

### Implementation Details

| Service | What runs inside | Volume | Network |
|---|---|---|---|
| Kafka | Kafka 4.4.0, KRaft broker + controller | `/var/lib/kafka/data` | 9092 private, 9093 via TCP proxy, `/healthz` on 8080 (private) |
| Kafka UI | Kafbat UI 1.5.1 (login form) | - | public domain, port 8080 |

**Connecting**

All client connections use `security.protocol=SASL_PLAINTEXT`, `sasl.mechanism=SCRAM-SHA-512` (SCRAM-SHA-256 also works), the user `KAFKA_SASL_USERNAME` (default `kafka`) and `KAFKA_SASL_PASSWORD` (generated).

- From Railway services: bootstrap `${{Kafka.KAFKA_BOOTSTRAP_SERVERS}}` (for example `kafka.railway.internal:9092`).
- From outside Railway: bootstrap `${{Kafka.KAFKA_PUBLIC_BOOTSTRAP_SERVERS}}` (the TCP proxy, for example `{proxy-host}:{proxy-port}`). SCRAM never sends the password itself, but the data on this connection is not encrypted; prefer the private network for sensitive data, or put a TLS tunnel in front.

Example `client.properties`:

```
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka" password="{password}";
```

**Kafka UI**

Open the **Kafka UI** domain and log in with `SPRING_SECURITY_USER_NAME` (default `admin`) and `SPRING_SECURITY_USER_PASSWORD` (generated). Browse topics, produce and read messages, and inspect consumer groups. Keep `AUTH_TYPE=LOGIN_FORM`.

**Variables**

| Variable | Default | Purpose |
|---|---|---|
| `KAFKA_SASL_USERNAME` / `KAFKA_SASL_PASSWORD` | `kafka` / generated | SCRAM user, re-applied at every start |
| `KAFKA_NUM_PARTITIONS` | `3` | Partitions of auto-created topics |
| `KAFKA_AUTO_CREATE_TOPICS` | `true` | Create topics on first use |
| `KAFKA_LOG_RETENTION_HOURS` | `168` | Retention (7 days) |
| `KAFKA_HEAP_MB` | auto (25% of memory, 256-1024 MB) | JVM heap |

The password may use letters, digits and `. _ ~ @ % ^ * + -` (12-128 characters). An invalid password locks the user with a random one and the log explains the fix; other invalid values fall back to defaults instead of crashing.

**Scaling and limits**

This is one KRaft node with replication factor 1: it is durable on its volume but not highly available. Scale vertically (RAM mostly goes to the OS page cache, which speeds up reads). Watch the volume size: retention, not consumption, deletes data. Adding more users or ACLs is possible with `kafka-configs.sh` and an authorizer, which this template does not enable (every authenticated user can do everything).

**Upgrades**

Eject the repo, change the tag and digest in `services/kafka/Dockerfile` after reading Kafka's upgrade notes (finalize the metadata version with `kafka-features.sh` afterwards), and redeploy. Pin Kafbat UI by changing its image tag and digest in the service settings.

**Resources**

Measured idle on Railway: Kafka about 0.8 GB with its default 1 GB heap (0.38 GB under the Trial plan's 1 GB limit), Kafka UI about 0.45 GB (0.25 GB under 1 GB). Both fit the Trial plan for light use; production traffic wants more RAM for the page cache. The Free plan (0.5 GB) is too small.

### Why Deploy Apache Kafka on Railway?

Railway gives Kafka a persistent volume, a private network with stable DNS names for your producers and consumers, a TCP proxy for outside clients and one-click upgrades of RAM. You get an authenticated broker and a web UI in a few minutes, without running ZooKeeper or Kubernetes. This is a community template, not affiliated with the Apache Software Foundation or Kafbat.
