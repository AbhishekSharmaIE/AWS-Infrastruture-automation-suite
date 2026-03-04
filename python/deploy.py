#!/usr/bin/env python3
"""
AWS Infrastructure Automation Suite - Main Deployment Orchestrator

Handles multi-region Terraform deployments with validation, drift detection,
cost estimation, and rollback capabilities.

Usage:
    python deploy.py plan   --project myproject --env dev
    python deploy.py apply  --project myproject --env staging --auto-approve
    python deploy.py destroy --project myproject --env dev
    python deploy.py cost   --project myproject --env prod
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

import boto3
import yaml
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn
from rich.table import Table
from rich.text import Text

# ─── Configuration ─────────────────────────────────────────────────────────────

console = Console()

LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(LOG_DIR / f"deploy_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"),
    ],
)
log = logging.getLogger("aws-infra-deploy")

VALID_ENVIRONMENTS = ["dev", "staging", "prod"]
REGIONS = {
    "dev":     {"primary": "us-east-1", "secondary": "us-west-2"},
    "staging": {"primary": "us-east-1", "secondary": "us-west-2"},
    "prod":    {"primary": "us-east-1", "secondary": "eu-west-1"},
}


@dataclass
class DeployConfig:
    project_name: str
    environment: str
    action: str
    primary_region: str = "us-east-1"
    secondary_region: str = "us-west-2"
    auto_approve: bool = False
    skip_validation: bool = False
    dry_run: bool = False
    extra_vars: dict = field(default_factory=dict)
    working_dir: Path = Path("terraform")


# ─── Pre-flight Validation ─────────────────────────────────────────────────────

class PreFlightValidator:
    """Validates all prerequisites before a deployment can proceed."""

    def __init__(self, config: DeployConfig):
        self.config = config
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def run_all(self) -> bool:
        checks = [
            ("AWS Credentials", self._check_aws_credentials),
            ("Terraform Version", self._check_terraform_version),
            ("Required Tools", self._check_required_tools),
            ("Environment Variables", self._check_environment_vars),
            ("State Backend", self._check_state_backend),
            ("Tfvars File", self._check_tfvars_file),
        ]

        with Progress(
            SpinnerColumn(), TextColumn("[progress.description]{task.description}"),
            console=console, transient=True,
        ) as progress:
            task = progress.add_task("Running pre-flight checks...", total=len(checks))
            for name, check in checks:
                progress.update(task, description=f"Checking {name}...")
                try:
                    check()
                except Exception as e:
                    self.errors.append(f"{name}: {e}")
                progress.advance(task)

        self._report()
        return len(self.errors) == 0

    def _check_aws_credentials(self):
        try:
            sts = boto3.client("sts", region_name=self.config.primary_region)
            identity = sts.get_caller_identity()
            log.info(f"AWS Identity: {identity['Arn']}")
            log.info(f"AWS Account: {identity['Account']}")
        except Exception as e:
            raise RuntimeError(f"AWS credential check failed: {e}")

    def _check_terraform_version(self):
        result = subprocess.run(
            ["terraform", "version", "-json"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError("Terraform not found. Install from https://terraform.io")

        version_data = json.loads(result.stdout)
        version = version_data["terraform_version"]
        major, minor, _ = (int(x) for x in version.split("."))

        if major < 1 or (major == 1 and minor < 5):
            raise RuntimeError(f"Terraform >= 1.5.0 required, found {version}")

        log.info(f"Terraform {version}")

    def _check_required_tools(self):
        tools = {"aws": True, "kubectl": False, "helm": False}
        for tool, required in tools.items():
            result = subprocess.run(["which", tool], capture_output=True)
            if result.returncode != 0:
                msg = f"Tool '{tool}' not found"
                if required:
                    raise RuntimeError(msg)
                self.warnings.append(f"{msg} (may be needed post-deploy)")
            else:
                log.info(f"Found: {tool}")

    def _check_environment_vars(self):
        required_if_no_tfvars = ["TF_VAR_alarm_email", "TF_VAR_domain_name"]
        tfvars_path = self.config.working_dir / "environments" / self.config.environment / "terraform.tfvars"

        if tfvars_path.exists():
            return

        missing = [v for v in required_if_no_tfvars if v not in os.environ]
        if missing:
            raise RuntimeError(
                f"No tfvars file found and missing env vars: {', '.join(missing)}"
            )

    def _check_state_backend(self):
        try:
            sts = boto3.client("sts", region_name=self.config.primary_region)
            account_id = sts.get_caller_identity()["Account"]
            bucket_name = f"tfstate-{self.config.project_name}-{self.config.environment}-{account_id}"
            s3 = boto3.client("s3", region_name=self.config.primary_region)
            s3.head_bucket(Bucket=bucket_name)
            log.info(f"State bucket: {bucket_name}")
        except Exception:
            self.warnings.append(
                "State bucket not found. Run 'make bootstrap' first."
            )

    def _check_tfvars_file(self):
        tfvars = self.config.working_dir / "environments" / self.config.environment / "terraform.tfvars"
        if not tfvars.exists():
            self.warnings.append(
                f"No tfvars at {tfvars}. Using defaults + environment variables."
            )

    def _report(self):
        table = Table(title="Pre-flight Check Results", show_lines=True)
        table.add_column("Status", style="bold", width=10)
        table.add_column("Detail")

        for err in self.errors:
            table.add_row("[red]ERROR[/red]", err)
        for warn in self.warnings:
            table.add_row("[yellow]WARN[/yellow]", warn)
        if not self.errors and not self.warnings:
