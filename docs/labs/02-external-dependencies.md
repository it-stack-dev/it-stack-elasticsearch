# Lab 05-02 — External Dependencies

**Module:** 05 — Elasticsearch search and log indexing  
**Duration:** See [lab manual](https://github.com/it-stack-dev/it-stack-docs)  
**Test Script:** 	ests/labs/test-lab-05-02.sh  
**Compose File:** docker/docker-compose.lan.yml

## Objective

Connect elasticsearch to external PostgreSQL and Redis on separate containers.

## Prerequisites

- Lab 05-01 passes
- External PostgreSQL and Redis accessible

## Steps

### 1. Prepare Environment

```bash
cd it-stack-elasticsearch
cp .env.example .env  # edit as needed
```

### 2. Start Services

```bash
make test-lab-02
```

Or manually:

```bash
docker compose -f docker/docker-compose.lan.yml up -d
```

### 3. Verify

```bash
docker compose ps
curl -sf http://localhost:9200/health
```

### 4. Run Test Suite

```bash
bash tests/labs/test-lab-05-02.sh
```

## Expected Results

All tests pass with FAIL: 0.

## Cleanup

```bash
docker compose -f docker/docker-compose.lan.yml down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.
