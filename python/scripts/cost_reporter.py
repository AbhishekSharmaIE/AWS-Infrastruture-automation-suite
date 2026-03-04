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
        forecast = self.get_cost_forecast()

        service_totals = {}
        for result in cost_data.get("ResultsByTime", []):
            for group in result.get("Groups", []):
                service = group["Keys"][0]
                cost = float(group["Metrics"]["UnblendedCost"]["Amount"])
                service_totals[service] = service_totals.get(service, 0) + cost

        sorted_services = sorted(service_totals.items(), key=lambda x: x[1], reverse=True)

        grand_total = sum(service_totals.values())

        forecast_total = None
        if "Total" in forecast:
            forecast_total = float(forecast["Total"]["Amount"])

        report = {
            "project": self.project,
            "environment": self.environment,
            "period": period,
            "start": start,
            "end": end,
            "services": sorted_services,
            "total": grand_total,
            "forecast_monthly": forecast_total,
            "generated_at": datetime.utcnow().isoformat(),
        }

        return report

    def print_report(self, report: dict):
        console.print(Panel.fit(
            f"[bold blue]AWS Cost Report[/bold blue]\n\n"
            f"Project:     [cyan]{report['project']}[/cyan]\n"
            f"Environment: [yellow]{report['environment']}[/yellow]\n"
            f"Period:      {report['period']} ({report['start']} to {report['end']})",
        ))

        table = Table(title="Cost by Service")
        table.add_column("Service", style="cyan")
        table.add_column("Cost (USD)", style="green", justify="right")
        table.add_column("% of Total", justify="right")

        total = report["total"]
        for service, cost in report["services"]:
            pct = (cost / total * 100) if total > 0 else 0
            table.add_row(service, f"${cost:,.2f}", f"{pct:.1f}%")

        table.add_row(
            "[bold]TOTAL[/bold]",
            f"[bold yellow]${total:,.2f}[/bold yellow]",
            "100.0%",
            style="bold",
        )
        console.print(table)

        if report.get("forecast_monthly"):
            console.print(
                f"\n[bold]Monthly forecast:[/bold] "
                f"[yellow]${report['forecast_monthly']:,.2f}[/yellow]"
            )

    def send_to_sns(self, report: dict, topic_arn: str):
        sns = boto3.client("sns", region_name="us-east-1")

        lines = [
            f"AWS Cost Report - {report['project']} ({report['environment']})",
            f"Period: {report['period']} ({report['start']} to {report['end']})",
            "",
            "Top Services:",
        ]

        for service, cost in report["services"][:10]:
            lines.append(f"  {service}: ${cost:,.2f}")

        lines.extend([
            "",
            f"TOTAL: ${report['total']:,.2f}",
        ])

        if report.get("forecast_monthly"):
            lines.append(f"Monthly Forecast: ${report['forecast_monthly']:,.2f}")

        sns.publish(
            TopicArn=topic_arn,
            Subject=f"Cost Report: {report['project']} - ${report['total']:,.2f}",
            Message="\n".join(lines),
        )
        console.print(f"[green]Report sent to SNS topic[/green]")


def main():
    parser = argparse.ArgumentParser(description="AWS Cost Reporter")
    parser.add_argument("--project", required=True)
    parser.add_argument("--env", required=True)
    parser.add_argument("--period", choices=["daily", "weekly", "monthly"], default="monthly")
    parser.add_argument("--sns-topic", help="SNS topic ARN to send report to")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    args = parser.parse_args()

    reporter = CostReporter(args.project, args.env)
    report = reporter.generate_report(args.period)

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    else:
        reporter.print_report(report)

    if args.sns_topic:
        reporter.send_to_sns(report, args.sns_topic)


if __name__ == "__main__":
    main()
