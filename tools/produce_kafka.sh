#!/usr/bin/env bash
# Produit des logs applicatifs JSON dans le topic Kafka app-logs (depuis le conteneur kafka).
# Usage : bash tools/produce_kafka.sh <hôte kafka> [nombre]
set -euo pipefail
HOST=${1:-ing01}; N=${2:-100}
levels=(INFO INFO INFO WARN ERROR DEBUG)
paths=(/api/orders /api/users /health /api/payments)

gen() {
  for i in $(seq 1 "$N"); do
    lvl=${levels[$((RANDOM % ${#levels[@]}))]}
    p=${paths[$((RANDOM % ${#paths[@]}))]}
    printf '{"timestamp":"%s","host":"app%02d","service":"shop","level":"%s","path":"%s","status":%d,"duration_ms":%d,"msg":"request %d","card":"4970123456789012"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%S+0000)" $((RANDOM%3+1)) "$lvl" "$p" \
      $([[ $lvl == ERROR ]] && echo 500 || echo 200) $((RANDOM%900)) "$i"
  done
}

gen | ssh "$HOST" "sudo podman exec -i kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic app-logs"
echo "$N messages produits. Splunk : index=app sourcetype=app:json | stats count by level, path"
echo "(les DEBUG sont filtrés par Logstash, /health par le nullQueue, et le numéro de carte est masqué par SEDCMD)"
