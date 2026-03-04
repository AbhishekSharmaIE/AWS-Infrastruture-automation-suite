#!/usr/bin/env python3
"""
Multi-region health checker with auto-remediation triggers.

Checks API endpoints, RDS clusters, ElastiCache, and EKS nodes across regions.
Publishes custom CloudWatch metrics for dashboarding and alerting.

Usage:
    python health_check.py --project myproject --env prod
    python health_check.py --project myproject --env prod --continuous --interval 60
"""

import argparse
import asyncio
import json
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Optional

import boto3
import httpx
from rich.console import Console
from rich.table import Table

console = Console()


@dataclass
class HealthResult:
    region: str
    service: str
    status: str       # healthy | degraded | unhealthy
    latency_ms: float
    details: dict
    timestamp: str = ""

    def __post_init__(self):
        if not self.timestamp:
            self.timestamp = datetime.utcnow().isoformat()


class MultiRegionHealthChecker:
    def __init__(self, project: str, environment: str, endpoints: Optional[dict] = None):
        self.project = project
        self.environment = environment
        self.endpoints = endpoints or {}

    async def check_all(self) -> list[HealthResult]:
        tasks = []

        for region, url in self.endpoints.items():
            tasks.append(self._check_endpoint(region, url))

        regions = list(self.endpoints.keys()) or ["us-east-1"]
        for region in regions:
            tasks.append(self._check_rds(region))
            tasks.append(self._check_elasticache(region))
            tasks.append(self._check_eks(region))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        health_results = []
        for r in results:
            if isinstance(r, HealthResult):
                health_results.append(r)
            elif isinstance(r, Exception):
                health_results.append(HealthResult(
                    region="unknown", service="check",
                    status="unhealthy", latency_ms=-1,
                    details={"error": str(r)},
                ))
        return health_results

    async def _check_endpoint(self, region: str, base_url: str) -> HealthResult:
        start = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=10.0, verify=True) as client:
                resp = await client.get(f"{base_url}/health")
                latency = (time.monotonic() - start) * 1000

                try:
                    data = resp.json()
                except Exception:
                    data = {"body": resp.text[:200]}

                if resp.status_code == 200:
                    status = "healthy"
                elif resp.status_code < 500:
                    status = "degraded"
                else:
                    status = "unhealthy"

                return HealthResult(
                    region=region, service="API",
                    status=status, latency_ms=latency,
                    details={"status_code": resp.status_code, **data},
                )
        except Exception as e:
            latency = (time.monotonic() - start) * 1000
            return HealthResult(
                region=region, service="API",
                status="unhealthy", latency_ms=latency,
                details={"error": str(e)},
            )

    async def _check_rds(self, region: str) -> HealthResult:
        start = time.monotonic()
        cluster_id = f"{self.project}-{self.environment}-aurora-primary"
        try:
            rds = boto3.client("rds", region_name=region)
            resp = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
            latency = (time.monotonic() - start) * 1000
            cluster = resp["DBClusters"][0]

            members = cluster.get("DBClusterMembers", [])
            writer_ok = any(m["IsClusterWriter"] for m in members)

            return HealthResult(
                region=region, service="Aurora",
                status="healthy" if cluster["Status"] == "available" and writer_ok else "degraded",
                latency_ms=latency,
                details={
                    "status": cluster["Status"],
                    "engine": cluster["EngineVersion"],
                    "members": len(members),
                    "multi_az": cluster.get("MultiAZ", False),
                },
            )
        except rds.exceptions.DBClusterNotFoundFault:
            return HealthResult(
                region=region, service="Aurora",
                status="unhealthy", latency_ms=-1,
                details={"error": f"Cluster {cluster_id} not found"},
            )
        except Exception as e:
            return HealthResult(
                region=region, service="Aurora",
                status="unhealthy", latency_ms=-1,
                details={"error": str(e)},
            )

    async def _check_elasticache(self, region: str) -> HealthResult:
        start = time.monotonic()
        group_id = f"{self.project}-{self.environment}"
        try:
            ec = boto3.client("elasticache", region_name=region)
            resp = ec.describe_replication_groups(ReplicationGroupId=group_id)
            latency = (time.monotonic() - start) * 1000
            group = resp["ReplicationGroups"][0]

            return HealthResult(
                region=region, service="Redis",
                status="healthy" if group["Status"] == "available" else "degraded",
                latency_ms=latency,
                details={
                    "status": group["Status"],
                    "nodes": len(group.get("NodeGroups", [{}])[0].get("NodeGroupMembers", [])),
                    "cluster_enabled": group.get("ClusterEnabled", False),
                },
            )
        except Exception as e:
            return HealthResult(
                region=region, service="Redis",
                status="unhealthy", latency_ms=-1,
                details={"error": str(e)},
            )

    async def _check_eks(self, region: str) -> HealthResult:
        start = time.monotonic()
        cluster_name = f"{self.project}-{self.environment}"
        try:
            eks = boto3.client("eks", region_name=region)
            resp = eks.describe_cluster(name=cluster_name)
            latency = (time.monotonic() - start) * 1000
            cluster = resp["cluster"]

            return HealthResult(
                region=region, service="EKS",
                status="healthy" if cluster["status"] == "ACTIVE" else "degraded",
                latency_ms=latency,
                details={
                    "status": cluster["status"],
                    "version": cluster["version"],
                    "platform_version": cluster.get("platformVersion", ""),
                },
            )
        except Exception as e:
            return HealthResult(
                region=region, service="EKS",
                status="unhealthy", latency_ms=-1,
                details={"error": str(e)},
            )

    def publish_metrics(self, results: list[HealthResult]):
        cw = boto3.client("cloudwatch", region_name="us-east-1")
        metric_data = []

        for r in results:
            metric_data.append({
                "MetricName": "ServiceHealth",
                "Dimensions": [
                    {"Name": "Region", "Value": r.region},
                    {"Name": "Service", "Value": r.service},
                    {"Name": "Environment", "Value": self.environment},
                ],
                "Value": 1.0 if r.status == "healthy" else (0.5 if r.status == "degraded" else 0.0),
                "Unit": "None",
                "Timestamp": datetime.utcnow(),
            })

            if r.latency_ms > 0:
                metric_data.append({
                    "MetricName": "ServiceLatency",
                    "Dimensions": [
                        {"Name": "Region", "Value": r.region},
                        {"Name": "Service", "Value": r.service},
                    ],
                    "Value": r.latency_ms,
                    "Unit": "Milliseconds",
                    "Timestamp": datetime.utcnow(),
                })

        for i in range(0, len(metric_data), 20):
            batch = metric_data[i : i + 20]
            cw.put_metric_data(
                Namespace=f"Custom/{self.project}",
                MetricData=batch,
            )

    def print_results(self, results: list[HealthResult]):
        table = Table(title=f"Health Check - {self.project}/{self.environment}")
        table.add_column("Region", style="cyan")
        table.add_column("Service", style="white")
        table.add_column("Status", style="bold")
        table.add_column("Latency", justify="right")
        table.add_column("Details")

        for r in sorted(results, key=lambda x: (x.region, x.service)):
            status_style = {
                "healthy": "[green]healthy[/green]",
                "degraded": "[yellow]degraded[/yellow]",
                "unhealthy": "[red]unhealthy[/red]",
            }.get(r.status, r.status)

            latency = f"{r.latency_ms:.0f}ms" if r.latency_ms >= 0 else "N/A"
            details_str = ", ".join(f"{k}={v}" for k, v in r.details.items() if k != "error")
            if "error" in r.details:
                details_str = f"[red]{r.details['error'][:60]}[/red]"

            table.add_row(r.region, r.service, status_style, latency, details_str)

        console.print(table)


async def run(args):
    endpoints = {}
    if args.endpoints:
        for ep in args.endpoints:
            region, url = ep.split("=", 1)
            endpoints[region] = url

    checker = MultiRegionHealthChecker(args.project, args.env, endpoints)

    while True:
        results = await checker.check_all()
        checker.print_results(results)

        if not args.json_only:
            try:
                checker.publish_metrics(results)
                console.print("[dim]Metrics published to CloudWatch[/dim]")
            except Exception as e:
                console.print(f"[yellow]Failed to publish metrics: {e}[/yellow]")

        if args.json_output:
            print(json.dumps([asdict(r) for r in results], indent=2, default=str))

        if not args.continuous:
            unhealthy = [r for r in results if r.status == "unhealthy"]
            return 1 if unhealthy else 0

        await asyncio.sleep(args.interval)


def main():
    parser = argparse.ArgumentParser(description="Multi-region infrastructure health checker")
    parser.add_argument("--project", required=True, help="Project name")
    parser.add_argument("--env", required=True, help="Environment")
    parser.add_argument("--endpoint", dest="endpoints", action="append",
                        help="region=url pairs for API health checks")
    parser.add_argument("--continuous", action="store_true", help="Run continuously")
    parser.add_argument("--interval", type=int, default=60, help="Seconds between checks (continuous mode)")
    parser.add_argument("--json-output", action="store_true", help="Also output JSON")
    parser.add_argument("--json-only", action="store_true", help="Skip CloudWatch metric publishing")
    args = parser.parse_args()

    return asyncio.run(run(args))


if __name__ == "__main__":
    exit(main() or 0)
