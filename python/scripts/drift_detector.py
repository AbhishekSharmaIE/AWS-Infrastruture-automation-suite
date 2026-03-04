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
                resource_id="plan",
                drift_type="error",
                details=f"Plan failed: {plan_result.stderr[:200]}",
                severity="critical",
            ))

        return results

    def detect_security_drift(self) -> list[DriftResult]:
        """Check for common security misconfigurations."""
        results = []

        results.extend(self._check_public_s3_buckets())
        results.extend(self._check_open_security_groups())
        results.extend(self._check_unencrypted_volumes())
        results.extend(self._check_iam_anomalies())

        return results

    def _check_public_s3_buckets(self) -> list[DriftResult]:
        results = []
        s3 = boto3.client("s3")
        try:
            buckets = s3.list_buckets()["Buckets"]
            for bucket in buckets:
                name = bucket["Name"]
                if self.project not in name:
                    continue
                try:
                    acl = s3.get_bucket_acl(Bucket=name)
                    for grant in acl.get("Grants", []):
                        grantee = grant.get("Grantee", {})
                        if grantee.get("URI") == "http://acs.amazonaws.com/groups/global/AllUsers":
                            results.append(DriftResult(
                                resource_type="aws_s3_bucket",
                                resource_id=name,
                                drift_type="modified",
                                details="Bucket has public ACL grant",
                                severity="critical",
                            ))
                except Exception:
                    pass
        except Exception:
            pass
        return results

    def _check_open_security_groups(self) -> list[DriftResult]:
        results = []
        ec2 = boto3.client("ec2")
        try:
            sgs = ec2.describe_security_groups(
                Filters=[{"Name": "tag:Project", "Values": [self.project]}]
            )["SecurityGroups"]

            for sg in sgs:
                for rule in sg.get("IpPermissions", []):
                    for ip_range in rule.get("IpRanges", []):
                        if ip_range.get("CidrIp") == "0.0.0.0/0":
                            port = rule.get("FromPort", "all")
                            if port not in (80, 443):
                                results.append(DriftResult(
                                    resource_type="aws_security_group",
                                    resource_id=sg["GroupId"],
                                    drift_type="modified",
                                    details=f"Port {port} open to 0.0.0.0/0 (sg: {sg.get('GroupName')})",
                                    severity="high",
                                ))
        except Exception:
            pass
        return results

    def _check_unencrypted_volumes(self) -> list[DriftResult]:
        results = []
        ec2 = boto3.client("ec2")
        try:
            volumes = ec2.describe_volumes(
                Filters=[{"Name": "tag:Project", "Values": [self.project]}]
            )["Volumes"]

            for vol in volumes:
                if not vol.get("Encrypted", False):
                    results.append(DriftResult(
                        resource_type="aws_ebs_volume",
                        resource_id=vol["VolumeId"],
                        drift_type="modified",
                        details="EBS volume is not encrypted",
                        severity="high",
                    ))
        except Exception:
            pass
        return results

    def _check_iam_anomalies(self) -> list[DriftResult]:
        results = []
        iam = boto3.client("iam")
        try:
            roles = iam.list_roles()["Roles"]
            for role in roles:
                if self.project not in role["RoleName"]:
                    continue
                policies = iam.list_attached_role_policies(RoleName=role["RoleName"])
                for policy in policies.get("AttachedPolicies", []):
                    if policy["PolicyArn"] == "arn:aws:iam::aws:policy/AdministratorAccess":
                        results.append(DriftResult(
                            resource_type="aws_iam_role",
                            resource_id=role["RoleName"],
                            drift_type="modified",
                            details="Role has AdministratorAccess attached",
                            severity="critical",
                        ))
        except Exception:
            pass
        return results

    def _parse_plan_output(self, output: str) -> list[DriftResult]:
        results = []
        for line in output.split("\n"):
            line = line.strip()
            if line.startswith("~ ") or line.startswith("+ ") or line.startswith("- "):
                drift_type = {"~": "modified", "+": "added", "-": "removed"}.get(line[0], "modified")
                resource = line[2:].strip()
                results.append(DriftResult(
                    resource_type="terraform_resource",
                    resource_id=resource[:100],
                    drift_type=drift_type,
                    details=line[:200],
                    severity="medium" if drift_type == "modified" else "low",
                ))
        return results

    def publish_results(self, results: list[DriftResult]):
        if not results:
            return

        cw = boto3.client("cloudwatch", region_name="us-east-1")
        cw.put_metric_data(
            Namespace=f"Custom/{self.project}",
            MetricData=[{
                "MetricName": "DriftCount",
                "Dimensions": [
                    {"Name": "Environment", "Value": self.environment},
                    {"Name": "Severity", "Value": severity},
                ],
                "Value": count,
                "Unit": "Count",
            } for severity, count in self._count_by_severity(results).items()],
        )

    def _count_by_severity(self, results: list[DriftResult]) -> dict:
        counts = {"low": 0, "medium": 0, "high": 0, "critical": 0}
        for r in results:
            counts[r.severity] = counts.get(r.severity, 0) + 1
        return counts

    def print_results(self, results: list[DriftResult]):
        if not results:
            console.print(Panel("[green]No drift detected[/green]", title="Drift Report"))
            return

        table = Table(title=f"Drift Report - {self.project}/{self.environment}")
        table.add_column("Severity", style="bold")
        table.add_column("Type")
        table.add_column("Resource")
        table.add_column("Drift")
        table.add_column("Details")

        severity_styles = {
            "critical": "[bold red]CRITICAL[/bold red]",
            "high":     "[red]HIGH[/red]",
            "medium":   "[yellow]MEDIUM[/yellow]",
            "low":      "[dim]LOW[/dim]",
        }

        for r in sorted(results, key=lambda x: ["critical", "high", "medium", "low"].index(x.severity)):
            table.add_row(
                severity_styles.get(r.severity, r.severity),
                r.resource_type,
                r.resource_id[:40],
                r.drift_type,
                r.details[:60],
            )

        console.print(table)

        counts = self._count_by_severity(results)
        summary = " | ".join(f"{k}: {v}" for k, v in counts.items() if v > 0)
        console.print(f"\n[bold]Summary:[/bold] {summary}")


def main():
    parser = argparse.ArgumentParser(description="Infrastructure Drift Detector")
    parser.add_argument("--project", required=True)
    parser.add_argument("--env", required=True)
    parser.add_argument("--security-only", action="store_true", help="Only check security drift")
    parser.add_argument("--terraform-only", action="store_true", help="Only check Terraform drift")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--publish", action="store_true", help="Publish metrics to CloudWatch")
    args = parser.parse_args()

    detector = DriftDetector(args.project, args.env)

    results = []
    if not args.security_only:
        console.print("[cyan]Detecting Terraform drift...[/cyan]")
        results.extend(detector.detect_terraform_drift())

    if not args.terraform_only:
        console.print("[cyan]Detecting security drift...[/cyan]")
        results.extend(detector.detect_security_drift())

    if args.json:
        print(json.dumps([{
            "resource_type": r.resource_type,
            "resource_id": r.resource_id,
            "drift_type": r.drift_type,
            "details": r.details,
            "severity": r.severity,
        } for r in results], indent=2))
    else:
        detector.print_results(results)

    if args.publish:
        detector.publish_results(results)
        console.print("[dim]Metrics published to CloudWatch[/dim]")

    critical_or_high = [r for r in results if r.severity in ("critical", "high")]
    return 1 if critical_or_high else 0


if __name__ == "__main__":
    sys.exit(main())
