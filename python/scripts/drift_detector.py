#!/usr/bin/env python3
"""
Infrastructure Drift Detector - Compares actual AWS state against Terraform state.

Detects configuration drift, unauthorized changes, and compliance violations.
Integrates with CloudWatch for alerting on drift events.

Usage:
    python drift_detector.py --project myproject --env prod
    python drift_detector.py --project myproject --env prod --fix --auto-approve
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import boto3
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

console = Console()


@dataclass
class DriftResult:
    resource_type: str
    resource_id: str
    drift_type: str    # added | removed | modified
    details: str
    severity: str      # low | medium | high | critical


class DriftDetector:
    def __init__(self, project: str, environment: str, working_dir: str = "terraform"):
        self.project = project
        self.environment = environment
        self.working_dir = Path(working_dir)

    def detect_terraform_drift(self) -> list[DriftResult]:
        """Run terraform plan to detect drift from desired state."""
        results = []

        plan_result = subprocess.run(
            ["terraform", "plan", "-detailed-exitcode", "-no-color",
             f"-var-file=environments/{self.environment}/terraform.tfvars"],
            capture_output=True, text=True,
            cwd=self.working_dir,
            env={
                **__import__("os").environ,
                "TF_VAR_project_name": self.project,
                "TF_VAR_environment": self.environment,
                "TF_IN_AUTOMATION": "1",
            },
        )

        if plan_result.returncode == 2:  # Changes detected
            results.extend(self._parse_plan_output(plan_result.stdout))
        elif plan_result.returncode != 0:
            results.append(DriftResult(
                resource_type="terraform",
