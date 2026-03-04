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
