"""
Remediation Executor Lambda
============================
Được gọi bởi Step Functions để thực thi remediation actions:
- block_ip: Block IP qua WAFv2 IP Set
- isolate_ec2: Cô lập EC2 instance bằng Isolation Security Group
- revoke_creds: Vô hiệu hóa IAM Access Keys
- reject: Ghi nhận analyst reject incident
- timeout: Ghi nhận approval timeout
- error: Ghi nhận lỗi trong workflow

Khi nhận flag wait_for_approval=true, Lambda lưu TaskToken vào DynamoDB
rồi return ngay (Step Functions sẽ pause chờ callback).
"""

import json
import logging
import os
import urllib.request
import urllib.parse
from datetime import datetime, timezone
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sts_client = boto3.client("sts")

DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "p2-soar-incidents")
DEVOPS_REMEDIATION_ROLE_ARN = os.environ.get("DEVOPS_REMEDIATION_ROLE_ARN", "")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

table = dynamodb.Table(DYNAMODB_TABLE)


def lambda_handler(event, context):
    """Entry point — invoked by Step Functions."""
    logger.info("Executor received: %s", json.dumps(event, default=str))

    incident_id = event.get("incident_id", "unknown")
    action_type = event.get("action_type", "unknown")
    target = event.get("target", "unknown")

    # ── Wait-for-approval path: save TaskToken → return immediately ──
    if event.get("wait_for_approval"):
        task_token = event.get("task_token")
        if not task_token:
            raise ValueError("wait_for_approval=true but no task_token provided")

        save_task_token(incident_id, task_token)
        send_telegram(
            f"⏳ <b>Awaiting Approval</b>\n"
            f"Incident: <code>{incident_id}</code>\n"
            f"Action: <code>{action_type}</code>\n"
            f"Target: <code>{target}</code>\n"
            f"🔗 Login to SOAR Portal to approve/reject."
        )
        # KHÔNG return output — Step Functions sẽ pause tại đây
        # Chờ callback Lambda gọi SendTaskSuccess/Failure
        return {"status": "waiting_for_approval", "incident_id": incident_id}

    # ── Execute path ──
    if action_type == "reject":
        update_status(incident_id, "reject", "Rejected")
        send_telegram(
            f"❌ <b>Rejected</b>\n"
            f"Incident: <code>{incident_id}</code>\n"
            f"Target: <code>{target}</code>"
        )
        return {"status": "rejected", "incident_id": incident_id}

    if action_type == "timeout":
        update_status(incident_id, "timeout", "Timed Out")
        send_telegram(
            f"⏰ <b>Approval Timed Out</b>\n"
            f"Incident: <code>{incident_id}</code>\n"
            f"Target: <code>{target}</code>"
        )
        return {"status": "timed_out", "incident_id": incident_id}

    if action_type == "error":
        error_info = event.get("error", {})
        logger.info("Updating error status for incident %s", incident_id)
        table.update_item(
            Key={"incident_id": incident_id},
            UpdateExpression="SET incident_status = :s, error_summary = :es, error_detail = :ed, failed_at = :t, retryable = :r, updated_at = :t",
            ExpressionAttributeValues={
                ":s": "Error",
                ":es": error_info.get("Error", "UnknownError"),
                ":ed": error_info.get("Cause", "No details available"),
                ":t": utc_now(),
                ":r": True
            }
        )
        send_telegram(
            f"🚨 <b>Workflow Error</b>\n"
            f"Incident: <code>{incident_id}</code>\n"
            f"Error: <code>{json.dumps(error_info, default=str)[:500]}</code>"
        )
        return {"status": "error", "incident_id": incident_id}

    # ── Actual remediation actions ──
    if action_type not in ("isolate_ec2", "revoke_creds", "block_ip"):
        raise ValueError(f"Unsupported action_type: {action_type}")

    clients = get_devops_clients()

    if action_type == "isolate_ec2":
        result = isolate_ec2(target, clients["ec2"])
    elif action_type == "revoke_creds":
        result = revoke_creds(target, clients["iam"])
    else:
        result = block_ip(target, clients["ec2"])

    update_status(incident_id, action_type, "Resolved")

    approved_by = event.get("approved_by", "auto")
    source = event.get("source", "unknown")
    send_telegram(
        f"✅ <b>Remediation Executed</b>\n"
        f"Incident: <code>{incident_id}</code>\n"
        f"Action: <code>{action_type}</code>\n"
        f"Target: <code>{target}</code>\n"
        f"Approved by: <code>{approved_by}</code>\n"
        f"Source: <code>{source}</code>\n"
        f"Result: <code>{json.dumps(result, default=str)[:300]}</code>"
    )

    return {"status": "executed", "incident_id": incident_id, "result": result}


# ── DynamoDB helpers ──

def save_task_token(incident_id, task_token):
    """Lưu SF TaskToken vào DynamoDB để callback Lambda lấy ra."""
    logger.info("Saving TaskToken for incident %s", incident_id)
    table.update_item(
        Key={"incident_id": incident_id},
        UpdateExpression="SET task_token = :t, incident_status = :s, updated_at = :u",
        ExpressionAttributeValues={
            ":t": task_token,
            ":s": "Pending Approval",
            ":u": utc_now(),
        },
    )


def update_status(incident_id, action, status):
    """Update incident status in DynamoDB."""
    logger.info("Updating incident %s → %s", incident_id, status)
    table.update_item(
        Key={"incident_id": incident_id},
        UpdateExpression="SET incident_status = :s, remediation_action = :a, updated_at = :t",
        ExpressionAttributeValues={
            ":s": status,
            ":a": action,
            ":t": utc_now(),
        },
    )


def utc_now():
    return datetime.now(timezone.utc).isoformat()


# ── Cross-account remediation ──

def get_devops_clients():
    if not DEVOPS_REMEDIATION_ROLE_ARN:
        raise RuntimeError("DEVOPS_REMEDIATION_ROLE_ARN is not configured")

    assumed = sts_client.assume_role(
        RoleArn=DEVOPS_REMEDIATION_ROLE_ARN,
        RoleSessionName="SFNRemediationExecutor",
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
                iam_client.update_access_key(
                    UserName=username, AccessKeyId=access_key_id, Status="Inactive"
                )
                revoked_keys.append(access_key_id)

    return {"revoked_keys": revoked_keys}


def block_ip(ip_address, ec2_client):
    logger.info("Blocking IP address %s via NACL", ip_address)
    if not ip_address or ip_address == "unknown":
        return {"error": "Invalid IP address"}

    # 1. Find VPC ID from ALB Security Group
    sgs = ec2_client.describe_security_groups(
        Filters=[{'Name': 'group-name', 'Values': ['p2-soar-dev-apse1-sg-alb']}]
    )
    if not sgs['SecurityGroups']:
        vpcs = ec2_client.describe_vpcs()
        if not vpcs['Vpcs']:
            raise RuntimeError("No VPC found in target account")
        vpc_id = vpcs['Vpcs'][0]['VpcId']
    else:
        vpc_id = sgs['SecurityGroups'][0]['VpcId']

    # 2. Get Network ACL for this VPC
    nacls = ec2_client.describe_network_acls(
        Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
    )
    if not nacls['NetworkAcls']:
        raise RuntimeError(f"No Network ACL found for VPC {vpc_id}")
    nacl = nacls['NetworkAcls'][0]
    nacl_id = nacl['NetworkAclId']

    # 3. Find an available rule number < 100
    existing_rule_numbers = {entry['RuleNumber'] for entry in nacl['Entries'] if not entry['Egress']}
    rule_number = None
    for r in range(10, 100):
        if r not in existing_rule_numbers:
            rule_number = r
            break
    if not rule_number:
        raise RuntimeError("No available rule numbers in NACL")

    # 4. Create deny rule for the IP
    ec2_client.create_network_acl_entry(
        NetworkAclId=nacl_id,
        RuleNumber=rule_number,
        Protocol='-1',  # All protocols
        RuleAction='deny',
        Egress=False,  # Inbound rule
        CidrBlock=f"{ip_address}/32"
    )

    return {
        "blocked_ip": ip_address,
        "nacl_id": nacl_id,
        "rule_number": rule_number,
        "method": "nacl_deny_entry"
    }


# ── Telegram notification ──

def send_telegram(message):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.info("Telegram not configured, skipping notification")
        return

    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = urllib.parse.urlencode({
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message,
            "parse_mode": "HTML",
        }).encode()
        req = urllib.request.Request(url, data=data)
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        logger.warning("Failed to send Telegram notification: %s", e)
