"""
Cost Anomaly Detection Lambda - Monitors AWS spending for unusual patterns.

Triggered on a schedule (daily via EventBridge). Compares current spending
against historical baselines and alerts on anomalies.

Environment Variables:
    PROJECT_NAME: Project identifier
    ENVIRONMENT: Deployment environment
    ALERTS_TOPIC_ARN: SNS topic for cost alerts
    ANOMALY_THRESHOLD_PCT: Percentage threshold for anomaly detection (default: 30)
"""

import json
import logging
import os
from datetime import datetime, timedelta

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

PROJECT = os.environ.get("PROJECT_NAME", "myproject")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")
ALERTS_TOPIC_ARN = os.environ.get("ALERTS_TOPIC_ARN", "")
ANOMALY_THRESHOLD_PCT = float(os.environ.get("ANOMALY_THRESHOLD_PCT", "30"))


def handler(event, context):
    """Check for cost anomalies by comparing recent spend to historical baseline."""
    log.info(f"Running cost anomaly detection for {PROJECT}/{ENVIRONMENT}")

    ce = boto3.client("ce", region_name="us-east-1")
    today = datetime.utcnow().date()

    yesterday_cost = _get_daily_cost(ce, today - timedelta(days=1), today)
    week_ago_start = today - timedelta(days=8)
    week_ago_end = today - timedelta(days=1)
    baseline_daily = _get_average_daily_cost(ce, week_ago_start, week_ago_end)

    log.info(f"Yesterday cost: ${yesterday_cost:.2f}, 7-day avg: ${baseline_daily:.2f}")

    anomalies = []

    if baseline_daily > 0:
        pct_change = ((yesterday_cost - baseline_daily) / baseline_daily) * 100
        if pct_change > ANOMALY_THRESHOLD_PCT:
            anomalies.append({
                "type": "daily_spend_spike",
                "yesterday": yesterday_cost,
                "baseline": baseline_daily,
                "pct_change": pct_change,
                "threshold": ANOMALY_THRESHOLD_PCT,
            })

    service_costs = _get_cost_by_service(ce, today - timedelta(days=1), today)
    baseline_services = _get_cost_by_service(ce, week_ago_start, week_ago_end)

    for service, cost in service_costs.items():
        baseline = baseline_services.get(service, 0) / 7
        if baseline > 1.0:
            pct = ((cost - baseline) / baseline) * 100
            if pct > ANOMALY_THRESHOLD_PCT * 1.5:
                anomalies.append({
                    "type": "service_cost_spike",
                    "service": service,
                    "yesterday": cost,
                    "daily_baseline": baseline,
                    "pct_change": pct,
                })

    if anomalies:
        log.warning(f"Detected {len(anomalies)} cost anomalies")
        _send_alert(anomalies, yesterday_cost, baseline_daily)
    else:
        log.info("No cost anomalies detected")

    return {
        "statusCode": 200,
        "anomalies_detected": len(anomalies),
        "yesterday_cost": yesterday_cost,
        "baseline_daily": baseline_daily,
    }


def _get_daily_cost(ce, start, end) -> float:
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": str(start), "End": str(end)},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        Filter={"Tags": {"Key": "Project", "Values": [PROJECT]}},
    )
    total = 0.0
    for result in resp.get("ResultsByTime", []):
        total += float(result["Total"]["UnblendedCost"]["Amount"])
    return total


def _get_average_daily_cost(ce, start, end) -> float:
    days = (end - start).days
    if days <= 0:
        return 0.0
    total = _get_daily_cost(ce, start, end)
    return total / days


def _get_cost_by_service(ce, start, end) -> dict[str, float]:
    resp = ce.get_cost_and_usage(
        TimePeriod={"Start": str(start), "End": str(end)},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        Filter={"Tags": {"Key": "Project", "Values": [PROJECT]}},
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )
    services = {}
    for result in resp.get("ResultsByTime", []):
        for group in result.get("Groups", []):
            svc = group["Keys"][0]
            cost = float(group["Metrics"]["UnblendedCost"]["Amount"])
            services[svc] = services.get(svc, 0) + cost
    return services


def _send_alert(anomalies: list, yesterday: float, baseline: float):
    if not ALERTS_TOPIC_ARN:
        log.warning("No ALERTS_TOPIC_ARN set, skipping notification")
        return

    lines = [
        f"Cost Anomaly Alert - {PROJECT} ({ENVIRONMENT})",
        f"Date: {datetime.utcnow().strftime('%Y-%m-%d')}",
        f"Yesterday's spend: ${yesterday:,.2f}",
        f"7-day daily average: ${baseline:,.2f}",
        "",
        f"Anomalies detected: {len(anomalies)}",
        "",
    ]

    for a in anomalies:
        if a["type"] == "daily_spend_spike":
            lines.append(
                f"DAILY SPEND SPIKE: ${a['yesterday']:,.2f} vs "
                f"${a['baseline']:,.2f} baseline (+{a['pct_change']:.1f}%)"
            )
        elif a["type"] == "service_cost_spike":
            lines.append(
                f"SERVICE SPIKE [{a['service']}]: ${a['yesterday']:,.2f} vs "
                f"${a['daily_baseline']:,.2f} baseline (+{a['pct_change']:.1f}%)"
            )

    sns = boto3.client("sns")
    sns.publish(
        TopicArn=ALERTS_TOPIC_ARN,
        Subject=f"Cost Anomaly: {PROJECT} - ${yesterday:,.2f} (+{((yesterday - baseline) / max(baseline, 0.01)) * 100:.0f}%)"[:100],
        Message="\n".join(lines),
    )
    log.info("Cost anomaly alert sent")
