#!/usr/bin/env python3
"""
AWS Cost Reporter - Generates detailed cost breakdowns using Cost Explorer API.

Produces daily/weekly/monthly reports with service-level breakdown,
trend analysis, and anomaly flagging. Sends reports via SNS or outputs to console.

Usage:
    python cost_reporter.py --project myproject --env prod --period monthly
    python cost_reporter.py --project myproject --env prod --period daily --sns-topic arn:...
"""

import argparse
import json
from datetime import datetime, timedelta

import boto3
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

console = Console()


class CostReporter:
    def __init__(self, project: str, environment: str):
        self.project = project
        self.environment = environment
        self.ce = boto3.client("ce", region_name="us-east-1")

    def get_cost_by_service(self, start: str, end: str) -> dict:
        resp = self.ce.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="DAILY",
            Metrics=["BlendedCost", "UnblendedCost", "UsageQuantity"],
            Filter={
                "Tags": {
                    "Key": "Project",
                    "Values": [self.project],
                }
            },
            GroupBy=[
                {"Type": "DIMENSION", "Key": "SERVICE"},
            ],
        )
        return resp

    def get_cost_forecast(self, days: int = 30) -> dict:
        today = datetime.utcnow().date()
        end = today + timedelta(days=days)
        try:
            resp = self.ce.get_cost_forecast(
                TimePeriod={"Start": str(today), "End": str(end)},
                Metric="UNBLENDED_COST",
                Granularity="MONTHLY",
                Filter={
                    "Tags": {
                        "Key": "Project",
                        "Values": [self.project],
                    }
                },
            )
            return resp
        except Exception as e:
            return {"error": str(e)}

    def generate_report(self, period: str = "monthly") -> dict:
        today = datetime.utcnow().date()

        if period == "daily":
            start = str(today - timedelta(days=1))
            end = str(today)
        elif period == "weekly":
            start = str(today - timedelta(days=7))
            end = str(today)
        else:
            start = str(today.replace(day=1))
            end = str(today)

        cost_data = self.get_cost_by_service(start, end)
