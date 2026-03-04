"""
Auto-Remediation Lambda - Triggered by CloudWatch Alarms via SNS.

Performs automated remediation actions based on alarm patterns:
- High CPU on Aurora -> Scale out read replicas
- Unhealthy ALB targets -> Trigger EKS node group refresh
- High Redis memory -> Publish notification for manual eviction
- Disk pressure on EKS -> Clean up old ECR images
- High 5XX rate -> Log circuit breaker alert

Environment Variables:
    PROJECT_NAME: Project identifier
    ENVIRONMENT: Deployment environment (dev/staging/prod)
    ALERTS_TOPIC_ARN: SNS topic for remediation notifications
"""

import json
import logging
import os
import time

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

PROJECT = os.environ.get("PROJECT_NAME", "myproject")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
ALERTS_TOPIC_ARN = os.environ.get("ALERTS_TOPIC_ARN", "")

MAX_AUTO_REPLICAS = 5
COOLDOWN_SECONDS = 300

_last_action_time: dict[str, float] = {}


REMEDIATION_MAP = {
    "HighCPU-Aurora":       "scale_out_aurora",
    "aurora-cpu":           "scale_out_aurora",
    "UnhealthyTargets":     "restart_unhealthy_pods",
    "unhealthy-hosts":      "restart_unhealthy_pods",
    "HighMemory-Redis":     "handle_redis_memory",
    "redis-memory":         "handle_redis_memory",
    "DiskPressure":         "cleanup_ecr_images",
    "High5XX":              "handle_high_error_rate",
    "alb-5xx":              "handle_high_error_rate",
}


def handler(event, context):
    """Lambda entry point. Processes SNS messages from CloudWatch Alarms."""
    log.info(f"Event: {json.dumps(event)}")

    for record in event.get("Records", []):
        try:
            message = json.loads(record["Sns"]["Message"])
        except (KeyError, json.JSONDecodeError) as e:
            log.error(f"Failed to parse SNS message: {e}")
            continue

        alarm_name = message.get("AlarmName", "")
        new_state = message.get("NewStateValue", "")
        old_state = message.get("OldStateValue", "")

        log.info(f"Alarm: {alarm_name} | {old_state} -> {new_state}")

        if new_state != "ALARM":
            log.info("State is not ALARM, skipping remediation")
            continue

        action_name = _match_action(alarm_name)
        if not action_name:
            log.warning(f"No remediation mapped for alarm: {alarm_name}")
            _notify(f"Unhandled alarm: {alarm_name}", message)
            continue

        if _in_cooldown(action_name):
            log.info(f"Action {action_name} is in cooldown, skipping")
            continue

        log.info(f"Executing remediation: {action_name}")
        try:
            action_fn = globals()[action_name]
            action_fn(message)
            _record_action(action_name)
            _notify(f"Remediation executed: {action_name}", message)
        except Exception as e:
            log.error(f"Remediation {action_name} failed: {e}")
            _notify(f"Remediation FAILED: {action_name} - {e}", message)

    return {"statusCode": 200, "body": "OK"}


def _match_action(alarm_name: str) -> str | None:
    for pattern, action in REMEDIATION_MAP.items():
        if pattern.lower() in alarm_name.lower():
            return action
    return None


def _in_cooldown(action: str) -> bool:
    last = _last_action_time.get(action, 0)
    return (time.time() - last) < COOLDOWN_SECONDS


def _record_action(action: str):
    _last_action_time[action] = time.time()


def _notify(subject: str, details: dict):
    if not ALERTS_TOPIC_ARN:
        return
    try:
        sns = boto3.client("sns")
        sns.publish(
            TopicArn=ALERTS_TOPIC_ARN,
            Subject=f"[{PROJECT}/{ENVIRONMENT}] {subject}"[:100],
            Message=json.dumps(details, indent=2, default=str),
        )
    except Exception as e:
        log.error(f"Failed to send notification: {e}")


# ─── Remediation Actions ──────────────────────────────────────────────────────

def scale_out_aurora(message: dict):
    """Add a read replica to the Aurora cluster if under the limit."""
    rds = boto3.client("rds")
    cluster_id = f"{PROJECT}-{ENVIRONMENT}-aurora-primary"

    clusters = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
    members = clusters["DBClusters"][0]["DBClusterMembers"]
    reader_count = sum(1 for m in members if not m["IsClusterWriter"])

    if reader_count >= MAX_AUTO_REPLICAS:
        log.info(f"Already at max replicas ({MAX_AUTO_REPLICAS}), skipping scale-out")
        return

    instance_id = f"{cluster_id}-auto-{int(time.time())}"
    rds.create_db_instance(
