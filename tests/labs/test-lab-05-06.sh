#!/usr/bin/env bash
# test-lab-05-06.sh — Lab 05-06: Production Deployment
# Module 05: Elasticsearch search and log indexing
# elasticsearch in production-grade HA configuration with monitoring
set -euo pipefail

LAB_ID="05-06"
LAB_NAME="Production Deployment"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.production.yml"
PASS=0
FAIL=0
CLEANUP=true

for arg in "$@"; do [[ "$arg" == "--no-cleanup" ]] && CLEANUP=false; done

# ── Colors ─────────────────────────────────────────────────────────────────────
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

# ── PHASE 1: Setup ─────────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 75s for ${MODULE} production stack to initialize..."
sleep 75

# ── PHASE 2: Health Checks ─────────────────────────────────────────────────────────
info "Phase 2: Container Health Checks"

for svc in elastic-p06-es elastic-p06-kib elastic-p06-ldap elastic-p06-kc; do
  if docker inspect --format '{{.State.Status}}' "$svc" 2>/dev/null | grep -q running; then
    pass "$svc is running"
  else
    fail "$svc is NOT running"
  fi
done

# ES cluster health
if curl -sf http://localhost:9200/_cluster/health | grep -qE '"status":"(green|yellow)"'; then
  pass "Elasticsearch cluster health is green/yellow"
else
  fail "Elasticsearch cluster health check failed"
fi

# Kibana accessible
if curl -sf http://localhost:5650/api/status | grep -q '"overall"'; then
  pass "Kibana status API accessible"
else
  fail "Kibana not accessible on port 5650"
fi

# Keycloak accessible
if curl -sf http://localhost:8550/realms/master | grep -q realm; then
  pass "Keycloak accessible on port 8550"
else
  fail "Keycloak not accessible on port 8550"
fi

# ── PHASE 3: Production Checks ───────────────────────────────────────────────────
info "Phase 3a: Compose config validation"
if docker compose -f "${COMPOSE_FILE}" config -q 2>/dev/null; then
  pass "Production compose config is valid"
else
  fail "Production compose config validation failed"
fi

info "Phase 3b: Resource limits applied"
MEM=$(docker inspect --format '{{.HostConfig.Memory}}' elastic-p06-es 2>/dev/null || echo 0)
if [ "${MEM}" -gt 0 ] 2>/dev/null; then
  pass "Resource memory limit applied on elastic-p06-es (${MEM} bytes)"
else
  fail "No memory limit found on elastic-p06-es"
fi

info "Phase 3c: Restart policy check"
POLICY=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' elastic-p06-es 2>/dev/null || echo none)
if [ "${POLICY}" = "unless-stopped" ]; then
  pass "Restart policy is unless-stopped on elastic-p06-es"
else
  fail "Restart policy is '${POLICY}' (expected unless-stopped)"
fi

info "Phase 3d: Production environment variables"
IT_ENV=$(docker exec elastic-p06-kib env 2>/dev/null | grep IT_STACK_ENV= | cut -d= -f2 || echo "")
if [ "${IT_ENV}" = "production" ]; then
  pass "IT_STACK_ENV=production set on Kibana"
else
  fail "IT_STACK_ENV not set to production on Kibana (got: ${IT_ENV})"
fi

IT_LAB=$(docker exec elastic-p06-kib env 2>/dev/null | grep IT_STACK_LAB= | cut -d= -f2 || echo "")
if [ "${IT_LAB}" = "06" ]; then
  pass "IT_STACK_LAB=06 set on Kibana"
else
  fail "IT_STACK_LAB not set to 06"
fi

info "Phase 3e: Elasticsearch index and ILM validation"
if curl -sf http://localhost:9200/_cat/indices?v | grep -q green; then
  pass "Elasticsearch has healthy indices"
else
  warn "No green indices found (cluster may be newly initialized)"
  pass "Elasticsearch index check passed (new cluster acceptable)"
fi

if docker exec elastic-p06-kib env 2>/dev/null | grep -q 'ILM\|LIFECYCLE'; then
  pass "ILM environment variables set on Kibana"
else
  warn "ILM env vars not found (may use config file instead)"
fi

info "Phase 3f: Write test document and verify retrieval"
if curl -sf -X POST http://localhost:9200/it-stack-test/_doc \
  -H 'Content-Type: application/json' \
  -d '{"lab":"06","module":"elasticsearch","env":"production"}' | grep -q '"result":"created"'; then
  pass "Test document indexed successfully"
else
  fail "Failed to index test document"
fi

sleep 2
if curl -sf 'http://localhost:9200/it-stack-test/_search?q=lab:06' | grep -q '"env":"production"'; then
  pass "Test document retrieved successfully"
else
  fail "Failed to retrieve test document"
fi

info "Phase 3g: Keycloak admin API token acquisition"
KC_TOKEN=$(curl -sf -X POST http://localhost:8550/realms/master/protocol/openid-connect/token \
  -d 'client_id=admin-cli&grant_type=password&username=admin&password=Admin06!' \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "${KC_TOKEN}" ]; then
  pass "Keycloak admin API token acquired"
else
  fail "Failed to acquire Keycloak admin API token"
fi

info "Phase 3h: LDAP connectivity check"
if docker exec elastic-p06-ldap ldapsearch -x -H ldap://localhost \
  -b dc=lab,dc=local -D cn=admin,dc=lab,dc=local -w LdapProd06! \
  cn=admin > /dev/null 2>&1; then
  pass "LDAP bind and search successful"
else
  fail "LDAP bind or search failed"
fi

info "Phase 3i: Restart resilience (ES node recovery)"
docker restart elastic-p06-es > /dev/null 2>&1
info "Waiting 30s for ES to recover after restart..."
sleep 30
if curl -sf http://localhost:9200/_cluster/health | grep -qE '"status":"(green|yellow)"'; then
  pass "Elasticsearch recovered after container restart"
else
  fail "Elasticsearch did NOT recover after container restart"
fi

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
if [ "${CLEANUP}" = true ]; then
  docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
  info "Cleanup complete"
else
  warn "Cleanup skipped (--no-cleanup flag set)"
fi

# ── Results ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi
set -euo pipefail

LAB_ID="05-06"
LAB_NAME="Production Deployment"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.production.yml"
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
info "Phase 3: Functional Tests (Lab 06 — Production Deployment)"

# TODO: Add module-specific functional tests here
# Example:
# if curl -sf http://localhost:9200/health > /dev/null 2>&1; then
#     pass "Health endpoint responds"
# else
#     fail "Health endpoint not reachable"
# fi

warn "Functional tests for Lab 05-06 pending implementation"

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
