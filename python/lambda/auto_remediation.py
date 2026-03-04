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

