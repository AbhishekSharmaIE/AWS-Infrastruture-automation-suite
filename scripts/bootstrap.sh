#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script - Creates S3 state bucket and DynamoDB lock table via CloudFormation.
# Usage: ./scripts/bootstrap.sh <project-name> <environment> [region]

PROJECT="${1:?Usage: $0 <project-name> <environment> [region]}"
ENV="${2:?Usage: $0 <project-name> <environment> [region]}"
REGION="${3:-us-east-1}"

STACK_NAME="${PROJECT}-${ENV}-bootstrap"
TEMPLATE="cloudformation/bootstrap.yaml"

echo "============================================"
echo "  AWS Infrastructure Bootstrap"
echo "============================================"
echo "  Project:     ${PROJECT}"
echo "  Environment: ${ENV}"
echo "  Region:      ${REGION}"
echo "  Stack:       ${STACK_NAME}"
echo "============================================"

if [[ ! -f "${TEMPLATE}" ]]; then
    echo "ERROR: Template not found: ${TEMPLATE}"
    echo "Run this script from the project root directory."
    exit 1
fi

echo ""
echo "Validating template..."
aws cloudformation validate-template \
    --template-body "file://${TEMPLATE}" \
    --region "${REGION}" > /dev/null

echo "Deploying bootstrap stack..."
aws cloudformation deploy \
    --template-file "${TEMPLATE}" \
    --stack-name "${STACK_NAME}" \
    --parameter-overrides \
        "ProjectName=${PROJECT}" \
        "Environment=${ENV}" \
    --region "${REGION}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --tags \
        "Project=${PROJECT}" \
        "Environment=${ENV}" \
        "ManagedBy=CloudFormation"

echo ""
echo "Retrieving outputs..."
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs' \
    --output table

echo ""
echo "Bootstrap complete. You can now run:"
echo "  make plan PROJECT=${PROJECT} ENV=${ENV}"
