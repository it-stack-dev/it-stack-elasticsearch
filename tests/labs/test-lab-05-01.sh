#!/usr/bin/env bash
# test-lab-05-01.sh — Lab 05-01: Standalone
# Module 05: Elasticsearch search and analytics engine
# Validates single-node cluster health, index creation, and document CRUD.
set -euo pipefail

LAB_ID="05-01"
LAB_NAME="Standalone"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.standalone.yml"
PASS=0
FAIL=0
ES_URL="http://localhost:9200"
NO_CLEANUP=${NO_CLEANUP:-0}

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

cleanup() {
    if [ "${NO_CLEANUP:-0}" = "1" ]; then
        info "NO_CLEANUP=1 — skipping teardown (containers left running)"
    else
        info "Phase 4: Cleanup"
        docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
        info "Cleanup complete"
    fi
}
trap cleanup EXIT

section() { echo -e "\n${CYAN}## $1${NC}"; }

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 90s for Elasticsearch to start..."
sleep 90

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps | grep -q "running\|Up"; then
    pass "2.1 es-s01-app container is running"
else
    fail "2.1 es-s01-app container is not running"
fi

if curl -sf "${ES_URL}/_cluster/health" | grep -q '"status":"green"\|"status":"yellow"'; then
    pass "2.2 Cluster health is green or yellow"
else
    fail "2.2 Cluster health check failed"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests"

# 3.1 Root endpoint returns cluster info
if curl -sf "${ES_URL}" | grep -q 'cluster_name\|version'; then
    pass "3.1 Root endpoint returns cluster metadata"
else
    fail "3.1 Root endpoint failed"
fi

# 3.2 Create index
if curl -sf -X PUT "${ES_URL}/lab-test-idx" \
        -H 'Content-Type: application/json' \
        -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}' \
        | grep -q '"acknowledged":true'; then
    pass "3.2 Index creation succeeded"
else
    fail "3.2 Index creation failed"
fi

# 3.3 Index a document
if curl -sf -X POST "${ES_URL}/lab-test-idx/_doc/1" \
        -H 'Content-Type: application/json' \
        -d '{"title":"IT-Stack ES Lab 05-01","status":"pass"}' \
        | grep -q '"result":"created"'; then
    pass "3.3 Document indexed successfully"
else
    fail "3.3 Document indexing failed"
fi

# 3.4 Retrieve document by ID
if curl -sf "${ES_URL}/lab-test-idx/_doc/1" | grep -q 'IT-Stack ES Lab 05-01'; then
    pass "3.4 Document retrieval by ID succeeded"
else
    fail "3.4 Document retrieval failed"
fi

# 3.5 Full-text search
if curl -sf -X GET "${ES_URL}/lab-test-idx/_search" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"match_all":{}}}' \
        | grep -q '"hits"'; then
    pass "3.5 Search query returned results"
else
    fail "3.5 Search query failed"
fi

# 3.6 Delete test index
curl -sf -X DELETE "${ES_URL}/lab-test-idx" > /dev/null 2>&1 || true
info "3.6 Test index removed"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
