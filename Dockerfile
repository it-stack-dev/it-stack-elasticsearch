# Dockerfile — IT-Stack ELASTICSEARCH wrapper
# Module 05 | Category: database | Phase: 4
# Base image: docker.elastic.co/elasticsearch/elasticsearch:8.13.0

FROM docker.elastic.co/elasticsearch/elasticsearch:8.13.0

# Labels
LABEL org.opencontainers.image.title="it-stack-elasticsearch" \
      org.opencontainers.image.description="Elasticsearch search and log indexing" \
      org.opencontainers.image.vendor="it-stack-dev" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/it-stack-dev/it-stack-elasticsearch"

# Copy custom configuration and scripts
COPY src/ /opt/it-stack/elasticsearch/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
