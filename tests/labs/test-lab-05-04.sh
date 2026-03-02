#!/usr/bin/env bash
# test-lab-05-04.sh — Lab 05-04: SSO Integration
# Module 05: Elasticsearch search and log indexing
# Services: Elasticsearch · Kibana · OpenLDAP · Keycloak
# Ports:    Kibana:5630  KC:8504  LDAP:3894
set -euo pipefail

LAB_ID="05-04"
LAB_NAME="SSO Integration"
MODULE="elasticsearch"
COMPOSE_FILE="docker/docker-compose.sso.yml"
KC_URL="http://localhost:8504"
KC_ADMIN="admin"
KC_PASS="Admin04!"
PASS=0
FAIL=0
CLEANUP=true

for arg in "$@"; do [ "$arg" = "--no-cleanup" ] && CLEANUP=false; done

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }

cleanup() {
  if [ "${CLEANUP}" = "true" ]; then
    info "Cleanup: bringing down ${MODULE} lab04 stack..."
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Lab ${LAB_ID}: ${LAB_NAME} — ${MODULE}${NC}"
echo -e "${CYAN}  Kibana OIDC + OpenLDAP + Keycloak authentication${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 90s for stack to initialize (ES + Kibana + LDAP + KC)..."
sleep 90

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

for svc in elastic-s04-es elastic-s04-kib elastic-s04-ldap elastic-s04-kc; do
  if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
    pass "Container ${svc} running"
  else
    fail "Container ${svc} not running"
  fi
done

if docker exec elastic-s04-es curl -sf -u elastic:ElasticLab04! \
     http://localhost:9200/_cluster/health > /dev/null 2>&1; then
  pass "Elasticsearch cluster health accessible"
else
  fail "Elasticsearch cluster health not accessible"
fi

if docker exec elastic-s04-ldap ldapsearch -x -H ldap://localhost \
     -b dc=lab,dc=local -D cn=admin,dc=lab,dc=local -w LdapLab04! \
     cn=admin > /dev/null 2>&1; then
  pass "OpenLDAP bind successful"
else
  fail "OpenLDAP bind failed"
fi

if curl -sf "${KC_URL}/realms/master" > /dev/null 2>&1; then
  pass "Keycloak master realm accessible"
else
  fail "Keycloak master realm not accessible"
fi

if curl -sf http://localhost:5630/api/status > /dev/null 2>&1; then
  pass "Kibana API accessible (:5630)"
else
  fail "Kibana API not accessible (:5630)"
fi

# ── PHASE 3: Functional Tests — SSO ───────────────────────────────────────────
section "Phase 3: Functional Tests — SSO Integration"

# ── 3a: Keycloak realm + OIDC client ──────────────────────────────────────────
info "Creating it-stack realm and kibana OIDC client via Keycloak API..."

KC_TOKEN=$(curl -sf -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN}&password=${KC_PASS}" \
  | grep -o '"access_token":"[^"]*' | cut -d'"' -f4 || echo "")

if [ -n "${KC_TOKEN}" ]; then
  pass "Keycloak admin token obtained"
else
  fail "Failed to get Keycloak admin token"
  KC_TOKEN=""
fi

if [ -n "${KC_TOKEN}" ]; then
  HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST "${KC_URL}/admin/realms" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"realm":"it-stack","enabled":true,"displayName":"IT-Stack Lab"}' || echo "000")
  if [ "${HTTP_STATUS}" = "201" ] || [ "${HTTP_STATUS}" = "409" ]; then
    pass "Keycloak it-stack realm created (status: ${HTTP_STATUS})"
  else
    fail "Failed to create it-stack realm (status: ${HTTP_STATUS})"
  fi
fi

if [ -n "${KC_TOKEN}" ]; then
  HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST "${KC_URL}/admin/realms/it-stack/clients" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"clientId":"kibana","enabled":true,"protocol":"openid-connect","redirectUris":["http://localhost:5630/*"]}' || echo "000")
  if [ "${HTTP_STATUS}" = "201" ] || [ "${HTTP_STATUS}" = "409" ]; then
    pass "Keycloak kibana OIDC client created (status: ${HTTP_STATUS})"
  else
    fail "Failed to create kibana OIDC client (status: ${HTTP_STATUS})"
  fi
fi

# Keycloak OIDC discovery
if curl -sf "${KC_URL}/realms/it-stack/.well-known/openid-configuration" | grep -q 'issuer'; then
  pass "Keycloak OIDC discovery returns issuer"
else
  fail "Keycloak OIDC discovery missing issuer"
fi

# Keycloak SAML descriptor
if curl -sf "${KC_URL}/realms/it-stack/protocol/saml/descriptor" | grep -q 'EntityDescriptor'; then
  pass "Keycloak SAML IdP metadata accessible"
else
  fail "Keycloak SAML metadata not accessible"
fi

# ── 3b: LDAP integration ──────────────────────────────────────────────────────
info "Testing LDAP integration..."

if docker exec elastic-s04-ldap ldapsearch -x -H ldap://localhost \
     -b dc=lab,dc=local -D cn=admin,dc=lab,dc=local -w LdapLab04! \
     '(objectClass=*)' dn 2>/dev/null | grep -q 'dn:'; then
  pass "LDAP base DC has entries"
else
  fail "LDAP base DC search returned no entries"
fi

if docker exec elastic-s04-kib curl -sf http://elastic-s04-kc:8080/realms/master > /dev/null 2>&1; then
  pass "Keycloak reachable from Kibana container"
else
  fail "Keycloak not reachable from Kibana container"
fi

# ── 3c: Keycloak and LDAP env vars in Kibana ──────────────────────────────────
if docker exec elastic-s04-kib env | grep -q 'KEYCLOAK_URL=http://elastic-s04-kc'; then
  pass "KEYCLOAK_URL env var set in Kibana container"
else
  fail "KEYCLOAK_URL not set in Kibana container"
fi

if docker exec elastic-s04-kib env | grep -q 'KEYCLOAK_REALM=it-stack'; then
  pass "KEYCLOAK_REALM env var set correctly"
else
  fail "KEYCLOAK_REALM not set in Kibana container"
fi

# ── 3d: Elasticsearch security checks ────────────────────────────────────────
info "Checking Elasticsearch security..."

if docker exec elastic-s04-es curl -sf -u elastic:ElasticLab04! \
     http://localhost:9200/ | grep -q 'cluster_name'; then
  pass "Elasticsearch responds with cluster info"
else
  fail "Elasticsearch cluster info not accessible"
fi

# ── 3e: Volume assertions ─────────────────────────────────────────────────────
for vol in elastic-s04-es-data elastic-s04-ldap-data elastic-s04-ldap-config; do
  if docker volume inspect "it-stack-elasticsearch-lab04_${vol}" > /dev/null 2>&1; then
    pass "Volume ${vol} exists"
  else
    fail "Volume ${vol} missing"
  fi
done

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}============================================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi

