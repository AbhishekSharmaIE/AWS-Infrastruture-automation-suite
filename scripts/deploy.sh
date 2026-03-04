#!/usr/bin/env bash
set -euo pipefail

# Deploy script - Wrapper around the Python orchestrator with environment setup.
# Usage: ./scripts/deploy.sh <action> <project> <environment> [extra-args...]
#   Actions: plan | apply | destroy | validate | cost

ACTION="${1:?Usage: $0 <action> <project> <environment> [extra-args...]}"
PROJECT="${2:?Usage: $0 <action> <project> <environment> [extra-args...]}"
ENV="${3:?Usage: $0 <action> <project> <environment> [extra-args...]}"
shift 3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

echo "============================================"
echo "  AWS Infrastructure Deploy"
echo "============================================"
echo "  Action:      ${ACTION}"
echo "  Project:     ${PROJECT}"
echo "  Environment: ${ENV}"
echo "============================================"

# Verify Python dependencies
if ! python3 -c "import rich, boto3, yaml" 2>/dev/null; then
    echo "Installing Python dependencies..."
    pip3 install -r "${PROJECT_DIR}/requirements.txt" --quiet
fi

# Check for required env vars if no tfvars
TFVARS="${PROJECT_DIR}/terraform/environments/${ENV}/terraform.tfvars"
if [[ ! -f "${TFVARS}" ]]; then
    echo "WARNING: No tfvars file found at ${TFVARS}"
    echo "Ensure TF_VAR_* environment variables are set."
fi

# Ensure we're in the project directory
cd "${PROJECT_DIR}"

# Run the orchestrator
exec python3 python/deploy.py "${ACTION}" \
    --project "${PROJECT}" \
    --env "${ENV}" \
    "$@"
