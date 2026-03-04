PROJECT ?= myproject
ENV     ?= dev
REGION  ?= us-east-1

PYTHON  := python3
TF_DIR  := terraform

.PHONY: help bootstrap init plan apply apply-auto destroy validate cost \
        health drift fmt lint clean update-kubeconfig dashboard test

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ─── Bootstrap & Init ──────────────────────────────────────────────────────────

bootstrap: ## Create S3 state bucket + DynamoDB lock table (one-time)
	@./scripts/bootstrap.sh $(PROJECT) $(ENV) $(REGION)

init: ## Initialize Terraform
	cd $(TF_DIR) && terraform init \
		-backend-config="bucket=tfstate-$(PROJECT)-$(ENV)" \
		-backend-config="region=$(REGION)" \
		-backend-config="key=$(ENV)/terraform.tfstate" \
		-backend-config="encrypt=true" \
		-upgrade

# ─── Terraform Operations ──────────────────────────────────────────────────────

plan: ## Generate Terraform plan
	$(PYTHON) python/deploy.py plan --project $(PROJECT) --env $(ENV)

apply: ## Apply Terraform plan (prompts for confirmation)
	$(PYTHON) python/deploy.py apply --project $(PROJECT) --env $(ENV)

apply-auto: ## Apply without confirmation (for CI/CD)
	$(PYTHON) python/deploy.py apply --project $(PROJECT) --env $(ENV) --auto-approve

destroy: ## Destroy infrastructure (with safety prompts)
	@./scripts/destroy.sh $(PROJECT) $(ENV)

validate: ## Validate Terraform configuration
	cd $(TF_DIR) && terraform validate

cost: ## Estimate monthly infrastructure cost
	$(PYTHON) python/deploy.py cost --project $(PROJECT) --env $(ENV)

# ─── Operations ────────────────────────────────────────────────────────────────

health: ## Run multi-region health checks
	$(PYTHON) python/scripts/health_check.py --project $(PROJECT) --env $(ENV)

drift: ## Detect infrastructure drift
	$(PYTHON) python/scripts/drift_detector.py --project $(PROJECT) --env $(ENV)

cost-report: ## Generate cost report
	$(PYTHON) python/scripts/cost_reporter.py --project $(PROJECT) --env $(ENV)

# ─── Code Quality ──────────────────────────────────────────────────────────────

fmt: ## Format all Terraform files
	cd $(TF_DIR) && terraform fmt -recursive

lint: ## Lint Terraform with tflint + tfsec
	@echo "Running tflint..."
	tflint --chdir $(TF_DIR) --recursive
	@echo "Running tfsec..."
	tfsec $(TF_DIR) --format lovely

lint-python: ## Lint Python code
	$(PYTHON) -m ruff check python/
	$(PYTHON) -m mypy python/ --ignore-missing-imports

test: ## Run Python tests
	$(PYTHON) -m pytest tests/ -v

# ─── Kubernetes ────────────────────────────────────────────────────────────────

update-kubeconfig: ## Configure kubectl for EKS cluster
	aws eks update-kubeconfig \
		--region $(REGION) \
		--name $(PROJECT)-$(ENV)

install-monitoring: ## Install Prometheus + Grafana on EKS
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install kube-prometheus-stack \
		prometheus-community/kube-prometheus-stack \
		--namespace monitoring --create-namespace \
		--values kubernetes/monitoring/prometheus-values.yaml

install-autoscaler: ## Install cluster autoscaler on EKS
	kubectl apply -f kubernetes/cluster-autoscaler.yaml

# ─── Utilities ─────────────────────────────────────────────────────────────────

dashboard: ## Open CloudWatch dashboard in browser
	@echo "https://$(REGION).console.aws.amazon.com/cloudwatch/home?region=$(REGION)#dashboards:name=$(PROJECT)-$(ENV)"

clean: ## Clean local Terraform state and logs
	find $(TF_DIR) -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find $(TF_DIR) -name "tfplan" -delete 2>/dev/null || true
	find $(TF_DIR) -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	find . -name "*.log" -delete 2>/dev/null || true
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned."

deps: ## Install Python dependencies
	pip3 install -r requirements.txt

tree: ## Show project structure
	@find . -not -path './.git/*' -not -path './.git' \
		-not -path './terraform/.terraform/*' \
		-not -path './__pycache__/*' \
		-not -name '*.pyc' \
		| sort | head -100
