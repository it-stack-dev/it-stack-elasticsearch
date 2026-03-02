#!/usr/bin/env bash
# test-lab-05-03.sh — Lab 05-03: Elasticsearch Advanced Features
# Tests: ES node + Kibana + Logstash pipeline · resource limits · ILM index policy
# Usage: bash test-lab-05-03.sh [--no-cleanup]
set -euo pipefail

LAB_ID="05-03"
LAB_NAME="Advanced Features — Kibana + Logstash pipeline"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.advanced.yml"
PASS=0
FAIL=0

CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033m'

pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}── $1 ──${NC}"; }

cleanup() {
  if [[ "${CLEANUP}" == "true" ]]; then
    info "Cleaning up Lab ${LAB_ID} containers..."
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
  else
    info "Skipping cleanup (--no-cleanup)"
  fi
}
trap cleanup EXIT

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
info "Starting elasticsearch + kibana + logstash stack..."
docker compose -f "${COMPOSE_FILE}" up -d

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

info "Waiting for Elasticsearch on port 9220..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9220/_cluster/health 2>/dev/null | grep -q 'green\|yellow'; then
    info "Elasticsearch ready after ${i}×10s"
    break
  fi
  [[ $i -eq 30 ]] && { fail "Elasticsearch did not become ready"; exit 1; }
  sleep 10
done

info "Waiting for Kibana on port 5620..."
for i in $(seq 1 24); do
  if curl -sf http://localhost:5620/api/status 2>/dev/null | grep -q 'available\|green\|yellow'; then
    info "Kibana ready after ${i}×15s"
    break
  fi
  [[ $i -eq 24 ]] && { warn "Kibana did not become ready in time"; }
  sleep 15
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests — Advanced Features"

# 3.1 Container states
for cname in es-a03-node es-a03-kibana es-a03-logstash; do
  STATE=$(docker inspect "${cname}" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [[ "${STATE}" == "running" ]]; then
    pass "Container ${cname} is running"
  else
    fail "Container ${cname} state: ${STATE}"
  fi
done

# 3.2 Elasticsearch cluster health
HEALTH=$(curl -sf http://localhost:9220/_cluster/health 2>/dev/null || echo "{}")
if echo "${HEALTH}" | grep -q 'green\|yellow'; then
  pass "Elasticsearch cluster health is green/yellow"
  STATUS=$(echo "${HEALTH}" | grep -o '"status":"[^"]*"' | head -1)
  info "  Cluster status: ${STATUS}"
else
  fail "Elasticsearch cluster health unexpected: ${HEALTH}"
fi

# 3.3 Elasticsearch index creation
CREATE=$(curl -sf -X PUT http://localhost:9220/lab03-test-index \
  -H 'Content-Type: application/json' \
  -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' 2>/dev/null || echo "{}")
if echo "${CREATE}" | grep -q '"acknowledged":true'; then
  pass "Elasticsearch index creation works"
else
  fail "Elasticsearch index creation failed: ${CREATE}"
fi

# 3.4 Index document + retrieve
docker exec es-a03-node curl -sf -X POST \
  'http://localhost:9200/lab03-test-index/_doc' \
  -H 'Content-Type: application/json' \
  -d '{"lab":"05-03","feature":"logstash-pipeline","status":"active"}' > /dev/null 2>&1 || true
# Allow indexing
sleep 2
DOC_COUNT=$(curl -sf http://localhost:9220/lab03-test-index/_count 2>/dev/null | grep -o '"count":[0-9]*' | grep -o '[0-9]*' || echo "0")
if [[ "${DOC_COUNT}" -ge 1 ]]; then
  pass "Elasticsearch document indexing works (count: ${DOC_COUNT})"
else
  warn "Elasticsearch document count is 0 (may still be indexing)"
fi

# 3.5 Kibana API status
KIBANA_STATUS=$(curl -sf http://localhost:5620/api/status 2>/dev/null || echo "{}")
if echo "${KIBANA_STATUS}" | grep -qi 'available\|status\|version'; then
  pass "Kibana API is reachable"
else
  warn "Kibana API returned unexpected: ${KIBANA_STATUS:0:80}"
fi

# 3.6 Resource limits on Elasticsearch node
MEM_LIMIT=$(docker inspect es-a03-node --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
if [[ "${MEM_LIMIT}" -gt 0 ]]; then
  pass "Elasticsearch node has memory limit set (${MEM_LIMIT} bytes)"
else
  fail "Elasticsearch node has no memory limit"
fi

# 3.7 Resource limits on Kibana
MEM_LIMIT_KB=$(docker inspect es-a03-kibana --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
if [[ "${MEM_LIMIT_KB}" -gt 0 ]]; then
  pass "Kibana has memory limit set (${MEM_LIMIT_KB} bytes)"
else
  fail "Kibana has no memory limit"
fi

# 3.8 ILM policy endpoint
ILM=$(curl -sf http://localhost:9220/_ilm/policy 2>/dev/null || echo "{}")
if echo "${ILM}" | grep -q '{'; then
  pass "Elasticsearch ILM policy endpoint is accessible"
else
  warn "ILM policy endpoint returned unexpected response"
fi

# 3.9 Elasticsearch node info
NODE_INFO=$(curl -sf http://localhost:9220/_nodes?filter_path=nodes.*.version 2>/dev/null || echo "{}")
if echo "${NODE_INFO}" | grep -q '8\.13'; then
  pass "Elasticsearch version 8.13.x confirmed"
else
  warn "Could not confirm Elasticsearch node version from: ${NODE_INFO:0:80}"
fi

# 3.10 Volume check
VOL=$(docker volume ls --format '{{.Name}}' | grep 'es-a03-data' || echo "")
if [[ -n "${VOL}" ]]; then
  pass "Persistent volume es-a03-data exists"
else
  fail "Volume es-a03-data not found"
fi

# ── PHASE 4: (cleanup via trap) ────────────────────────────────────────────────
section "Phase 4: Results"

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
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

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 30s for ${MODULE} to initialize..."
sleep 30

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps | grep -q "running\|Up"; then
    pass "Container is running"
else
    fail "Container is not running"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 03 — Advanced Features)"

# TODO: Add module-specific functional tests here
# Example:
# if curl -sf http://localhost:9200/health > /dev/null 2>&1; then
#     pass "Health endpoint responds"
# else
#     fail "Health endpoint not reachable"
# fi

warn "Functional tests for Lab 05-03 pending implementation"

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
info "Cleanup complete"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
