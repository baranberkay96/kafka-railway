# NOTICE: Apache Kafka template

This is a community template. It is not made, endorsed or supported by the Apache Software Foundation, the Kafbat project or Railway. Apache Kafka and Kafka are trademarks of the Apache Software Foundation.

## Components

| Component | Source | License | How it is used |
|---|---|---|---|
| Apache Kafka 4.4.0 (`apache/kafka:4.4.0@sha256:833b867a9585a141da455dc2b57431c65cbccb27f11c91f694444cca9f777e0f`, Alpine, Eclipse Temurin 25 JRE) | https://github.com/apache/kafka | Apache-2.0 | Official image as the base; `python3` and `su-exec` added from Alpine |
| Kafbat UI 1.5.1 (`kafbat/kafka-ui:v1.5.1@sha256:c0585fdfed6a9b8adedc3b0965113d4a84f292d61e58a2c7dcc603394defb7d1`) | https://github.com/kafbat/kafka-ui | Apache-2.0 | Official image, unmodified |

## Files written for this template

`services/kafka/Dockerfile`, `railway-kafka.sh`, `railway-kafka-users.sh`, `railway-healthz.py` (adapted from our own GitHub Runner template) and the documentation were written for this template and are offered under the MIT License.

## Upstream files checked

- apache/kafka 4.4.0: `docker/jvm/Dockerfile` (Alpine, `appuser`, `/var/lib/kafka/data`), KRaft and SCRAM sections of the documentation (`kafka-storage.sh format --add-scram`, `kafka-configs.sh --add-config SCRAM-SHA-512=[...]`).
- kafbat/kafka-ui v1.5.1: environment-variable configuration (`KAFKA_CLUSTERS_0_*`, `AUTH_TYPE=LOGIN_FORM`, `SPRING_SECURITY_USER_*`).

## Market templates

The Kafka templates on the Railway marketplace and our own Redpanda template were reviewed for features only. No third-party files or text were copied.
