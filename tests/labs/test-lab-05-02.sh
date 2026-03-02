#!/usr/bin/env bash
# test-lab-05-02.sh — Lab 05-02: External Dependencies
# Module 05: Elasticsearch search and log indexing
# elasticsearch with external PostgreSQL, Redis, and network integration
set -euo pipefail

LAB_ID="05-02"
LAB_NAME="External Dependencies"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.lan.yml"
PASS=0
FAIL=0

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── Cleanup control ───────────────────────────────────────────────────────────
CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

cleanup() {
  if [[ "${CLEANUP}" == "true" ]]; then
    info "Phase 4: Cleanup"
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
    info "Cleanup complete"
  else
    info "Skipping cleanup (--no-cleanup)"
  fi
}
trap cleanup EXIT

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

info "Waiting for Elasticsearch node (es-l02-node, up to 150s)..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9210/_cluster/health 2>/dev/null | grep -q 'green\|yellow'; then
    pass "Elasticsearch cluster healthy"
    break
  fi
  [[ $i -eq 30 ]] && fail "Elasticsearch timed out after 150s"
  sleep 5
done

info "Waiting for Kibana (es-l02-kibana, up to 180s)..."
for i in $(seq 1 36); do
  if curl -sf http://localhost:5610/api/status 2>/dev/null | grep -q 'available\|green\|yellow'; then
    pass "Kibana status endpoint available"
    break
  fi
  [[ $i -eq 36 ]] && fail "Kibana timed out after 180s"
  sleep 5
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 05-02 — External Dependencies)"

# Container states
for svc in es-l02-node es-l02-kibana; do
  state=$(docker inspect --format='{{.State.Status}}' "${svc}" 2>/dev/null || echo "missing")
  if [[ "${state}" == "running" ]]; then
    pass "Container ${svc} is running"
  else
    fail "Container ${svc} state: ${state}"
  fi
done

# ES cluster health detail
health=$(curl -sf http://localhost:9210/_cluster/health 2>/dev/null || echo "{}")
if echo "${health}" | grep -q '"status":"green"\|"status":"yellow"'; then
  pass "ES cluster status is green or yellow"
else
  fail "ES cluster health unexpected: ${health}"
fi

# ES node count
nodes=$(curl -sf http://localhost:9210/_cat/nodes 2>/dev/null | wc -l | tr -d ' ')
if [[ "${nodes}" -ge 1 ]]; then
  pass "ES cluster has ${nodes} node(s)"
else
  fail "ES cluster node count: ${nodes}"
fi

# Index CRUD test
info "Testing index create/write/read/delete..."
curl -sf -X PUT "http://localhost:9210/lab02-test" -H 'Content-Type: application/json' \
  -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' > /dev/null 2>&1
curl -sf -X POST "http://localhost:9210/lab02-test/_doc/1" -H 'Content-Type: application/json' \
  -d '{"lab":"05-02","message":"external-dep-test","status":"pass"}' > /dev/null 2>&1
read_doc=$(curl -sf "http://localhost:9210/lab02-test/_doc/1" 2>/dev/null || echo "{}")
if echo "${read_doc}" | grep -q 'external-dep-test'; then
  pass "Index CRUD: document written and read back successfully"
else
  fail "Index CRUD: document read-back failed"
fi
curl -sf -X DELETE "http://localhost:9210/lab02-test" > /dev/null 2>&1 || true

# Kibana API status check
kibana_status=$(curl -sf http://localhost:5610/api/status 2>/dev/null || echo "{}")
if echo "${kibana_status}" | grep -q 'status\|overall'; then
  pass "Kibana API /api/status responds with status information"
else
  fail "Kibana API /api/status did not return expected data"
fi

# Network separation: data-net and app-net exist
for net in it-stack-elasticsearch-lab02_es-l02-data-net it-stack-elasticsearch-lab02_es-l02-app-net; do
  if docker network ls --format '{{.Name}}' | grep -q "${net}"; then
    pass "Network ${net} exists"
  else
    fail "Network ${net} missing"
  fi
done

# Volume exists
if docker volume ls --format '{{.Name}}' | grep -q 'es-l02-data'; then
  pass "ES data volume es-l02-data exists"
else
  fail "ES data volume missing"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
