#!/bin/bash
# entrypoint.sh — IT-Stack elasticsearch container entrypoint
set -euo pipefail

echo "Starting IT-Stack ELASTICSEARCH (Module 05)..."

# Source any environment overrides
if [ -f /opt/it-stack/elasticsearch/config.env ]; then
    # shellcheck source=/dev/null
    source /opt/it-stack/elasticsearch/config.env
fi

# Execute the upstream entrypoint or command
exec "$$@"
