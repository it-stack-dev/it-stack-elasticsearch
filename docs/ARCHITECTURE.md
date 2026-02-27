# Architecture — IT-Stack ELASTICSEARCH

## Overview

Elasticsearch provides full-text search for Nextcloud and log indexing for Graylog.

## Role in IT-Stack

- **Category:** database
- **Phase:** 4
- **Server:** lab-db1 (10.0.50.12)
- **Ports:** 9200 (REST API), 9300 (Cluster)

## Dependencies

| Dependency | Type | Required For |
|-----------|------|--------------|
| FreeIPA | Identity | User directory |
| Keycloak | SSO | Authentication |
| PostgreSQL | Database | Data persistence |
| Redis | Cache | Sessions/queues |
| Traefik | Proxy | HTTPS routing |

## Data Flow

```
User → Traefik (HTTPS) → elasticsearch → PostgreSQL (data)
                       ↗ Keycloak (auth)
                       ↗ Redis (sessions)
```

## Security

- All traffic over TLS via Traefik
- Authentication delegated to Keycloak OIDC
- Database credentials via Ansible Vault
- Logs shipped to Graylog
