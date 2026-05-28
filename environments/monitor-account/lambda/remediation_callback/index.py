"""
Remediation Callback Lambda
=============================
Được gọi từ API Gateway khi analyst click Approve/Reject trên Web Portal.
Lấy TaskToken từ DynamoDB → gọi Step Functions SendTaskSuccess hoặc SendTaskFailure
để resume workflow đang pause tại WaitForApproval state.
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sfn_client = boto3.client("stepfunctions")

DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "p2-soar-incidents")

table = dynamodb.Table(DYNAMODB_TABLE)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
}


def lambda_handler(event, context):
    """API Gateway → callback Lambda entry point."""
    logger.info("Callback received: %s", json.dumps(event, default=str))

    http_method = event.get("httpMethod", "")

    # Handle CORS preflight
    if http_method == "OPTIONS":
        return response(200, "")

    try:
        body = parse_body(event)
        incident_id = body.get("incident_id")
        decision = body.get("decision")  # "approved" or "rejected"

        if not incident_id or not decision:
            return response(400, {"error": "Missing required fields: incident_id, decision"})

        if decision not in ("approved", "rejected"):
            return response(400, {"error": "decision must be 'approved' or 'rejected'"})

        # Extract analyst info from Cognito JWT claims (set by API Gateway Authorizer)
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        approved_by = claims.get("email") or claims.get("cognito:username") or "unknown"

        # Get TaskToken from DynamoDB
        item = table.get_item(Key={"incident_id": incident_id}).get("Item")
        if not item:
            return response(404, {"error": f"Incident {incident_id} not found"})

        task_token = item.get("task_token")
        if not task_token:
            return response(409, {
                "error": f"Incident {incident_id} has no pending approval (no task_token). "
                         "It may have been auto-executed or already processed."
            })

        # Send callback to Step Functions
        if decision == "approved":
            sfn_client.send_task_success(
                taskToken=task_token,
                output=json.dumps({
                    "decision": "approved",
                    "approved_by": approved_by,
                    "decided_at": utc_now(),
                }),
            )
            logger.info("Sent TaskSuccess for incident %s (approved by %s)", incident_id, approved_by)
        else:
            sfn_client.send_task_failure(
                taskToken=task_token,
                error="AnalystRejected",
                cause=f"Rejected by {approved_by} at {utc_now()}",
            )
            logger.info("Sent TaskFailure for incident %s (rejected by %s)", incident_id, approved_by)

        # Clear task_token from DynamoDB (prevent duplicate callbacks)
        table.update_item(
            Key={"incident_id": incident_id},
            UpdateExpression="REMOVE task_token SET updated_at = :t, decided_by = :d",
            ExpressionAttributeValues={
                ":t": utc_now(),
                ":d": approved_by,
            },
        )

        return response(200, {
            "message": f"Incident {incident_id} {decision} by {approved_by}",
            "incident_id": incident_id,
            "decision": decision,
            "decided_by": approved_by,
        })

    except sfn_client.exceptions.TaskTimedOut:
        return response(410, {"error": "Approval window has expired (Step Functions task timed out)"})
    except sfn_client.exceptions.TaskDoesNotExist:
        return response(410, {"error": "Task no longer exists in Step Functions (may have been cancelled)"})
    except Exception as exc:
        logger.exception("Error processing callback")
        return response(500, {"error": str(exc)})


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": body if isinstance(body, str) else json.dumps(body, default=str),
    }


def parse_body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        body = base64.b64decode(body).decode("utf-8")
    if isinstance(body, str):
        return json.loads(body or "{}")
    return body


def utc_now():
    return datetime.now(timezone.utc).isoformat()
