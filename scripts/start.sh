#!/bin/bash
# Start all infrastructure
set -e

PROJECT_ID="infra-learning-pdtung1605"
REGION="asia-southeast1"

echo "=== Starting Staging ==="
cd "$(dirname "$0")/../terraform/environments/staging"
terraform init -input=false
terraform apply -auto-approve -var="project_id=$PROJECT_ID"

echo ""
echo "=== Starting Prod ==="
cd "../prod"
terraform init -input=false
terraform apply -auto-approve -var="project_id=$PROJECT_ID"

echo ""
echo "=== Getting credentials ==="
gcloud container clusters get-credentials staging-cluster --zone "${REGION}-a" --project "$PROJECT_ID"
gcloud container clusters get-credentials prod-cluster --region "$REGION" --project "$PROJECT_ID"

echo ""
echo "✅ Both clusters ready!"
echo "kubectl config get-contexts"
