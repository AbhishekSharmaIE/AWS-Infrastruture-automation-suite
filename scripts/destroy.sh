#!/usr/bin/env bash
set -euo pipefail

# Destroy script - Tears down infrastructure with safety checks.
# Usage: ./scripts/destroy.sh <project> <environment>

PROJECT="${1:?Usage: $0 <project> <environment>}"
ENV="${2:?Usage: $0 <project> <environment>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "============================================"
echo "  AWS Infrastructure DESTROY"
echo "============================================"
echo "  Project:     ${PROJECT}"
echo "  Environment: ${ENV}"
echo "============================================"
echo ""

if [[ "${ENV}" == "prod" ]]; then
    echo "╔══════════════════════════════════════════╗"
    echo "║  WARNING: PRODUCTION ENVIRONMENT         ║"
    echo "║  This will destroy ALL infrastructure    ║"
    echo "║  including databases and stored data.    ║"
    echo "║  This action CANNOT be undone.           ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    read -rp "Type the project name to confirm: " CONFIRM_PROJECT
    if [[ "${CONFIRM_PROJECT}" != "${PROJECT}" ]]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi
    read -rp "Type 'destroy-prod' to proceed: " CONFIRM_DESTROY
    if [[ "${CONFIRM_DESTROY}" != "destroy-prod" ]]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi
else
    read -rp "Destroy ${PROJECT}/${ENV}? (y/N): " CONFIRM
    if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
        echo "Aborting."
        exit 0
    fi
fi

cd "${PROJECT_DIR}"

echo ""
echo "Step 1: Removing Kubernetes resources..."
if command -v kubectl &>/dev/null; then
    kubectl delete namespace monitoring --ignore-not-found --timeout=60s 2>/dev/null || true
    echo "  Kubernetes cleanup done."
else
    echo "  kubectl not found, skipping."
fi

echo ""
echo "Step 2: Running Terraform destroy..."
python3 python/deploy.py destroy \
    --project "${PROJECT}" \
    --env "${ENV}" \
    --auto-approve \
    --skip-validation

echo ""
echo "Step 3: Cleaning up local state..."
rm -rf terraform/.terraform terraform/tfplan
find . -name "*.log" -delete 2>/dev/null || true

echo ""
echo "============================================"
echo "  Destroy complete."
echo "============================================"
echo ""
echo "NOTE: The bootstrap stack (S3 + DynamoDB) was NOT destroyed."
echo "To remove it:"
echo "  aws cloudformation delete-stack --stack-name ${PROJECT}-${ENV}-bootstrap"
