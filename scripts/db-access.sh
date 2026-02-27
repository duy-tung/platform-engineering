#!/bin/bash
# Level 2 DB Access: Temporary IAM + Auth Proxy
# Usage: ./scripts/db-access.sh [duration_hours] [user_email]

set -euo pipefail

PROJECT="infra-learning-pdtung1605"
INSTANCE="infra-learning-pdtung1605:asia-southeast1:platform-db"
DURATION_HOURS="${1:-2}"
USER="${2:-$(gcloud auth list --filter=status:ACTIVE --format='value(account)')}"

# Calculate expiry
EXPIRY=$(date -u -v+${DURATION_HOURS}H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
         date -u -d "+${DURATION_HOURS} hours" '+%Y-%m-%dT%H:%M:%SZ')

echo "🔐 Granting temporary Cloud SQL access"
echo "   User:     ${USER}"
echo "   Duration: ${DURATION_HOURS}h"
echo "   Expires:  ${EXPIRY}"
echo ""

# Grant temporary IAM binding with condition
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="user:${USER}" \
  --role="roles/cloudsql.client" \
  --condition="expression=request.time < timestamp('${EXPIRY}'),title=temp-db-access-$(date +%s),description=Temporary DB access for ${USER}" \
  --quiet > /dev/null

echo "✅ IAM granted. Starting Auth Proxy..."
echo "   Connect with: psql -h 127.0.0.1 -U platform-admin -d platform"
echo "   Password: gcloud secrets versions access latest --secret=platform-db-password"
echo "   Ctrl+C to disconnect"
echo ""

# Start Auth Proxy
cloud-sql-proxy "${INSTANCE}" --port=5432
