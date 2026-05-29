import json
import logging
import os
import time
from datetime import datetime, timezone
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sfn_client = boto3.client("stepfunctions")

DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "project2-soar-incidents")
table = dynamodb.Table(DYNAMODB_TABLE)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event, default=str))

    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    if http_method == "OPTIONS":
        return response(200, "")

    try:
        if http_method == "GET" and path.endswith("/incidents"):
            return response(200, {"incidents": list_incidents()})

        if http_method == "POST" and path.endswith("/retry"):
            return handle_retry(event)

        return response(400, {"error": "Invalid endpoint or method"})

    except Exception as exc:
        logger.exception("Error processing request")
        return response(500, {"error": str(exc)})


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": body if isinstance(body, str) else json.dumps(body, default=json_default),
    }


def parse_body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        body = base64.b64decode(body).decode("utf-8")
    if isinstance(body, str):
        return json.loads(body or "{}")
    return body


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"{type(value).__name__} is not JSON serializable")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def public_incident(item):
    return {
        "incident_id": item.get("incident_id"),
        "timestamp": item.get("timestamp"),
        "severity": item.get("severity"),
        "summary": item.get("summary") or item.get("incident_title"),
        "action_type": item.get("action_type") or item.get("remediation_action"),
        "target": item.get("target") or item.get("source_ip") or item.get("destination_ip"),
        "source_ip": item.get("source_ip"),
        "destination_ip": item.get("destination_ip"),
        "incident_status": item.get("incident_status") or item.get("status"),
        "updated_at": item.get("updated_at"),
        "decided_by": item.get("decided_by"),
        "decided_at": item.get("decided_at"),
        "error_summary": item.get("error_summary"),
        "error_detail": item.get("error_detail"),
        "retry_count": int(item.get("retry_count", 0)),
        "retryable": item.get("retryable", False),
        "has_pending_approval": bool(item.get("task_token")),
    }


def list_incidents(limit=500):
    response_data = table.scan()
    items = response_data.get("Items", [])
    items.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    return [public_incident(item) for item in items[:limit]]


def handle_retry(event):
    body = parse_body(event)
    incident_id = body.get("incident_id")
    if not incident_id:
        return response(400, {"error": "Missing incident_id"})
    
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    retried_by = claims.get("email") or claims.get("cognito:username") or "unknown"
    
    item = table.get_item(Key={"incident_id": incident_id}).get("Item")
    if not item:
        return response(404, {"error": "Incident not found"})
        
    if item.get("incident_status") != "Error" and not item.get("retryable"):
        return response(400, {"error": "Incident is not in an error state or is not retryable"})
        
    sfn_arn = os.environ.get("SFN_STATE_MACHINE_ARN")
    if not sfn_arn:
        return response(500, {"error": "SFN_STATE_MACHINE_ARN not configured"})
        
    sfn_payload = {
        "incident_id": incident_id,
        "action_type": item.get("action_type") or item.get("remediation_action"),
        "target": item.get("target") or item.get("source_ip") or item.get("destination_ip"),
        "source": "WebPortal_Retry",
        "auto_execute": False
    }
    
    try:
        sfn_client.start_execution(
            stateMachineArn=sfn_arn,
            input=json.dumps(sfn_payload)
        )
    except Exception as e:
        logger.exception("Failed to start Step Functions execution")
        return response(500, {"error": f"Failed to start workflow: {str(e)}"})
        
    retry_count = int(item.get("retry_count", 0)) + 1
    table.update_item(
        Key={"incident_id": incident_id},
        UpdateExpression="SET incident_status = :s, retry_count = :rc, retried_by = :rb, updated_at = :t REMOVE error_summary, error_detail, failed_at, retryable",
        ExpressionAttributeValues={
            ":s": "Pending Approval",
            ":rc": retry_count,
            ":rb": retried_by,
            ":t": utc_now()
        }
    )
    
    return response(200, {"message": f"Retry started for {incident_id}", "retry_count": retry_count})
