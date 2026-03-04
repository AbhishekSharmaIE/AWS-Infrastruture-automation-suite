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
