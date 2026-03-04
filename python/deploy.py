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
