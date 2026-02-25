#!/bin/bash
# Stop all infrastructure to save costs
set -e

PROJECT_ID="infra-learning-pdtung1605"

echo "=== Destroying Staging ==="
cd "$(dirname "$0")/../terraform/environments/staging"
terraform init -input=false
terraform destroy -auto-approve -var="project_id=$PROJECT_ID"

echo ""
echo "=== Destroying Prod ==="
cd "../prod"
terraform init -input=false
terraform destroy -auto-approve -var="project_id=$PROJECT_ID"

echo ""
echo "✅ All resources destroyed. Cost: ~$0/month"
echo "   Terraform state preserved on GCS — run start.sh to recreate"
