#!/bin/bash
# start-synapse.sh - Start Synapse Matrix Homeserver
# Synapse listens on port 6167 (same as Tuwunel) so all existing routing works unchanged.

# Skip if not using Synapse provider
if [ "${HICLAW_MATRIX_PROVIDER:-tuwunel}" != "synapse" ]; then
    echo "[hiclaw] Matrix provider is '${HICLAW_MATRIX_PROVIDER:-tuwunel}', skipping Synapse"
    exec sleep infinity
fi

SYNAPSE_DATA="/data/synapse"
SYNAPSE_CONFIG="${SYNAPSE_DATA}/homeserver.yaml"
mkdir -p "${SYNAPSE_DATA}"

# Generate homeserver.yaml if not exists (use Synapse's native flag, not Docker start.py)
# Note: --server-name includes port to match Tuwunel's CONDUWUIT_SERVER_NAME format,
# which is used in Matrix user IDs (e.g., @user:matrix-local.hiclaw.io:18080).
if [ ! -f "${SYNAPSE_CONFIG}" ]; then
    echo "[hiclaw] Generating Synapse homeserver.yaml..."
    python3 -m synapse.app.homeserver \
        --generate-config \
        --server-name "${HICLAW_MATRIX_DOMAIN:-matrix-local.hiclaw.io:8080}" \
        --config-path "${SYNAPSE_CONFIG}" \
        --data-directory "${SYNAPSE_DATA}" \
        --report-stats no
fi

# Patch config on every startup (passwords/secrets may change between restarts)
if [ -z "${HICLAW_PG_HOST}" ]; then
    echo "[hiclaw] ERROR: HICLAW_PG_HOST is required for Synapse provider"
    exit 1
fi
echo "[hiclaw] Patching Synapse config..."
HICLAW_PG_HOST="${HICLAW_PG_HOST:-}" \
HICLAW_PG_USER="${HICLAW_PG_USER:-synapse}" \
HICLAW_PG_PASSWORD="${HICLAW_PG_PASSWORD}" \
HICLAW_PG_DATABASE="${HICLAW_PG_DATABASE:-synapse}" \
HICLAW_PG_PORT="${HICLAW_PG_PORT:-5432}" \
HICLAW_SYNAPSE_SHARED_SECRET="${HICLAW_SYNAPSE_SHARED_SECRET}" \
python3 -c "
import yaml, os

with open('${SYNAPSE_CONFIG}') as f:
    config = yaml.safe_load(f)

# PostgreSQL database (read credentials from env to avoid shell injection)
config['database'] = {
    'name': 'psycopg2',
    'args': {
        'user': os.environ['HICLAW_PG_USER'],
        'password': os.environ['HICLAW_PG_PASSWORD'],
        'database': os.environ['HICLAW_PG_DATABASE'],
        'host': os.environ['HICLAW_PG_HOST'],
        'port': int(os.environ['HICLAW_PG_PORT']),
        'cp_min': 5,
        'cp_max': 10,
    }
}

# Registration
config['registration_shared_secret'] = os.environ['HICLAW_SYNAPSE_SHARED_SECRET']
config['enable_registration'] = False

# Rate limits (Synapse defaults are too strict for agent workflows)
config['rc_message'] = {'per_second': 5, 'burst_count': 30}
config['rc_registration'] = {'per_second': 3, 'burst_count': 10}
config['rc_login'] = {
    'address': {'per_second': 3, 'burst_count': 10},
    'account': {'per_second': 3, 'burst_count': 10},
    'failed_attempts': {'per_second': 3, 'burst_count': 10},
}
config['rc_joins'] = {
    'local': {'per_second': 5, 'burst_count': 20},
    'remote': {'per_second': 3, 'burst_count': 10},
}

# Listener on port 6167 (same as Tuwunel for transparent switching)
config['listeners'] = [{
    'port': 6167,
    'tls': False,
    'type': 'http',
    'x_forwarded': True,
    'bind_addresses': ['0.0.0.0'],
    'resources': [{'names': ['client', 'federation'], 'compress': False}],
}]

with open('${SYNAPSE_CONFIG}', 'w') as f:
    yaml.dump(config, f, default_flow_style=False)
print('[hiclaw] Synapse config patched')
"

exec python3 -m synapse.app.homeserver --config-path "${SYNAPSE_CONFIG}"
