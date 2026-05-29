import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sts_client = boto3.client("sts")
sfn_client = boto3.client("stepfunctions")

DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "project2-soar-incidents")
DEVOPS_REMEDIATION_ROLE_ARN = os.environ.get("DEVOPS_REMEDIATION_ROLE_ARN", "")

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

        body = parse_body(event)
        incident_id = body.get("incident_id")
        action_type = body.get("action_type")
        target = body.get("target")

        should_capture = is_alert_payload(body) or not (incident_id and action_type and target)
        incident = save_incident(body) if should_capture else None

        if not incident_id or not action_type or not target:
            return response(
                202,
                {
                    "message": "Incident captured and queued for analysis",
                    "incident": incident,
                },
            )

        logger.info("Executing %s for target %s (Incident: %s)", action_type, target, incident_id)

        if action_type == "reject":
            result = {"status": "rejected"}
            status_to_set = "Rejected"
        elif action_type in ("isolate_ec2", "revoke_creds", "block_ip"):
            clients = get_devops_clients()
            if action_type == "isolate_ec2":
                result = isolate_ec2(target, clients["ec2"])
            elif action_type == "revoke_creds":
                result = revoke_creds(target, clients["iam"])
            else:
                result = block_ip(target, clients["waf"])
            status_to_set = "Resolved"
        else:
            return response(400, {"error": f"Unsupported action_type: {action_type}"})

        update_dynamodb_status(incident_id, action_type, status_to_set)

        message = (
            f"Action {action_type} executed successfully on {target}"
            if action_type != "reject"
            else "Incident rejected successfully"
        )
        return response(200, {"message": message, "details": result})

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


def is_alert_payload(body):
    alert_fields = [
        "severity",
        "summary",
        "message",
        "timestamp",
        "@timestamp",
        "source",
        "destination",
        "rule",
        "kibana",
    ]
    return any(field in body for field in alert_fields)


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"{type(value).__name__} is not JSON serializable")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def get_nested(data, dotted_path):
    current = data
    for part in dotted_path.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def first_present(data, candidates, default=None):
    for candidate in candidates:
        value = get_nested(data, candidate) if "." in candidate else data.get(candidate)
        if value not in (None, ""):
            return value
    return default


def normalize_incident(raw):
    timestamp = first_present(raw, ["timestamp", "@timestamp", "event.created"], utc_now())
    incident_id = first_present(raw, ["incident_id", "rule.id", "alert.id"])

    if not incident_id:
        incident_id = f"inc-{int(time.time())}-{uuid.uuid4().hex[:8]}"

    source_ip = first_present(raw, ["source_ip", "source.ip", "client.ip"])
    destination_ip = first_present(raw, ["destination_ip", "destination.ip", "server.ip"])
    target = first_present(
        raw,
        ["target", "host.name", "cloud.instance.id", "user.name"],
        source_ip or destination_ip or "unknown",
    )
    action_type = first_present(raw, ["action_type", "recommended_action"], "block_ip" if source_ip else "isolate_ec2")

    return {
        "incident_id": str(incident_id),
        "timestamp": str(timestamp),
        "severity": str(first_present(raw, ["severity", "kibana.alert.severity", "event.severity"], "High")).title(),
        "summary": str(first_present(raw, ["summary", "message", "rule.name", "kibana.alert.rule.name"], "Elastic SIEM alert received")),
        "action_type": str(action_type),
        "target": str(target),
        "source_ip": str(source_ip or ""),
        "destination_ip": str(destination_ip or ""),
        "incident_status": str(first_present(raw, ["incident_status", "status"], "Pending Approval")),
        "raw_alert": raw,
        "updated_at": utc_now(),
        "ttl": int(time.time()) + (90 * 24 * 60 * 60),
    }


def sanitize_for_dynamodb(value):
    if isinstance(value, dict):
        return {key: sanitize_for_dynamodb(item) for key, item in value.items()}
    if isinstance(value, list):
        return [sanitize_for_dynamodb(item) for item in value]
    if isinstance(value, float):
        return Decimal(str(value))
    return value


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


def save_incident(raw):
    incident = normalize_incident(raw)
    logger.info("Saving incident %s to DynamoDB", incident["incident_id"])
    table.put_item(Item=sanitize_for_dynamodb(incident))
    return incident


def list_incidents(limit=500):
    response_data = table.scan()
    items = response_data.get("Items", [])
    items.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    return [public_incident(item) for item in items[:limit]]


def get_devops_clients():
    if not DEVOPS_REMEDIATION_ROLE_ARN:
        raise RuntimeError("DEVOPS_REMEDIATION_ROLE_ARN is not configured for cross-account remediation")

    assumed = sts_client.assume_role(
        RoleArn=DEVOPS_REMEDIATION_ROLE_ARN,
        RoleSessionName="MonitorRemediationLambda",
    )
    creds = assumed["Credentials"]
    session = boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )

    return {
        "ec2": session.client("ec2"),
        "iam": session.client("iam"),
        "waf": session.client("wafv2"),
    }


def isolate_ec2(instance_id, ec2_client):
    logger.info("Isolating EC2 instance %s", instance_id)

    instances = ec2_client.describe_instances(InstanceIds=[instance_id])
    vpc_id = instances["Reservations"][0]["Instances"][0]["VpcId"]

    sgs = ec2_client.describe_security_groups(
        Filters=[
            {"Name": "vpc-id", "Values": [vpc_id]},
            {"Name": "group-name", "Values": ["Isolation-SG"]},
        ]
    )

    if not sgs["SecurityGroups"]:
        created = ec2_client.create_security_group(
            GroupName="Isolation-SG",
            Description="Used to isolate compromised instances",
            VpcId=vpc_id,
        )
        sg_id = created["GroupId"]
        ec2_client.revoke_security_group_egress(
            GroupId=sg_id,
            IpPermissions=[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}],
        )
    else:
        sg_id = sgs["SecurityGroups"][0]["GroupId"]

    ec2_client.modify_instance_attribute(InstanceId=instance_id, Groups=[sg_id])
    return {"isolated_sg": sg_id}


def revoke_creds(username, iam_client):
    logger.info("Revoking credentials for user %s", username)
    paginator = iam_client.get_paginator("list_access_keys")
    revoked_keys = []

    for page in paginator.paginate(UserName=username):
        for key in page["AccessKeyMetadata"]:
            if key["Status"] == "Active":
                access_key_id = key["AccessKeyId"]
                iam_client.update_access_key(UserName=username, AccessKeyId=access_key_id, Status="Inactive")
                revoked_keys.append(access_key_id)

    return {"revoked_keys": revoked_keys}


def block_ip(ip_address, waf_client):
    logger.info("Blocking IP address %s", ip_address)
    return {"blocked_ip": ip_address, "method": "mock_waf_ipset_update"}


def update_dynamodb_status(incident_id, action, status):
    logger.info("Updating DynamoDB incident %s to status %s", incident_id, status)
    table.update_item(
        Key={"incident_id": incident_id},
        UpdateExpression="SET incident_status = :s, remediation_action = :a, updated_at = :t",
        ExpressionAttributeValues={
            ":s": status,
            ":a": action,
            ":t": utc_now(),
        },
    )

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
