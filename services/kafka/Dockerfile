# syntax=docker/dockerfile:1
#
# Apache Kafka 4.4.0 (KRaft, single broker) for Railway.
#
# Base: the official apache/kafka image (Alpine, Temurin 25 JRE), multi-arch
# index digest checked 2026-11-24. Added: python3 (private /healthz for
# Railway's healthcheck) and su-exec (drop to appuser after fixing the
# volume's ownership), both from Alpine's repositories.
FROM apache/kafka:4.4.0@sha256:833b867a9585a141da455dc2b57431c65cbccb27f11c91f694444cca9f777e0f

USER root
RUN apk add --no-cache python3 su-exec

COPY --chmod=0755 railway-kafka.sh /usr/local/bin/railway-kafka
COPY --chmod=0755 railway-kafka-users.sh /usr/local/bin/railway-kafka-users
COPY --chmod=0755 railway-healthz.py /usr/local/bin/railway-healthz

ENV PORT=8080
EXPOSE 9092 9093 8080

ENTRYPOINT ["/usr/local/bin/railway-kafka"]
