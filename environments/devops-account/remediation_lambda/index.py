import json
import boto3
import os
import logging
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2_client = boto3.client('ec2')
iam_client = boto3.client('iam')
waf_client = boto3.client('wafv2')
dynamodb = boto3.resource('dynamodb')

DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE', 'p2-soar-incidents')
table = dynamodb.Table(DYNAMODB_TABLE)

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")

    # Support API Gateway integration (CORS and body parsing)
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
    }

    http_method = event.get('httpMethod', '')
    path = event.get('path', '')

    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }

    if http_method == 'GET' and path.endswith('/incidents'):
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({'incidents': list_incidents()}, default=json_default)
        }

    try:
        body = parse_body(event)
        incident_id = body.get('incident_id')
        action_type = body.get('action_type')
        target = body.get('target')

        should_capture = is_alert_payload(body) or not (incident_id and action_type and target)
        incident = save_incident(body) if should_capture else None

        if not incident_id or not action_type or not target:
            return {
                'statusCode': 202,
                'headers': headers,
                'body': json.dumps({
                    'message': 'Incident captured and queued for analysis',
                    'incident': incident
                }, default=json_default)
            }

        logger.info(f"Executing {action_type} for target {target} (Incident: {incident_id})")

        result = {'status': 'success'}

        if action_type == 'isolate_ec2':
            # Create a simple isolate security group and attach it
            result = isolate_ec2(target)
        elif action_type == 'revoke_creds':
            result = revoke_creds(target)
        elif action_type == 'block_ip':
            result = block_ip(target)
        elif action_type == 'reject':
            result = {'status': 'rejected'}
        else:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': f'Unsupported action_type: {action_type}'})
            }

        # Update DynamoDB status after an analyst-approved remediation or an
        # explicit automation payload from Elastic.
        status_to_set = 'Rejected' if action_type == 'reject' else 'Resolved'
        update_dynamodb_status(incident_id, action_type, status_to_set)

        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': f'Action {action_type} executed successfully on {target}' if action_type != 'reject' else 'Incident rejected successfully',
                'details': result
            })
        }

    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }

def parse_body(event):
    body = event.get('body') or '{}'

    if event.get('isBase64Encoded'):
        import base64
        body = base64.b64decode(body).decode('utf-8')

    if isinstance(body, str):
        return json.loads(body or '{}')

    return body

def is_alert_payload(body):
    alert_fields = [
        'severity',
        'summary',
        'message',
        'timestamp',
        '@timestamp',
        'source',
        'destination',
        'rule',
        'kibana'
    ]
    return any(field in body for field in alert_fields)

def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f'{type(value).__name__} is not JSON serializable')

def utc_now():
    return datetime.now(timezone.utc).isoformat()

def get_nested(data, dotted_path):
    current = data
    for part in dotted_path.split('.'):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current

def first_present(data, candidates, default=None):
    for candidate in candidates:
        value = get_nested(data, candidate) if '.' in candidate else data.get(candidate)
        if value not in (None, ''):
            return value
    return default

def normalize_incident(raw):
    timestamp = first_present(raw, ['timestamp', '@timestamp', 'event.created'], utc_now())
    incident_id = first_present(raw, ['incident_id', 'rule.id', 'alert.id'])

    if not incident_id:
        incident_id = f"inc-{int(time.time())}-{uuid.uuid4().hex[:8]}"

    source_ip = first_present(raw, ['source_ip', 'source.ip', 'client.ip'])
    destination_ip = first_present(raw, ['destination_ip', 'destination.ip', 'server.ip'])
    target = first_present(raw, ['target', 'host.name', 'cloud.instance.id', 'user.name'], source_ip or destination_ip or 'unknown')
    action_type = first_present(raw, ['action_type', 'recommended_action'], 'block_ip' if source_ip else 'isolate_ec2')

    return {
        'incident_id': str(incident_id),
        'timestamp': str(timestamp),
        'severity': str(first_present(raw, ['severity', 'kibana.alert.severity', 'event.severity'], 'High')).title(),
        'summary': str(first_present(raw, ['summary', 'message', 'rule.name', 'kibana.alert.rule.name'], 'Elastic SIEM alert received')),
        'action_type': str(action_type),
        'target': str(target),
        'source_ip': str(source_ip or ''),
        'destination_ip': str(destination_ip or ''),
        'incident_status': str(first_present(raw, ['incident_status', 'status'], 'Pending Approval')),
        'raw_alert': raw,
        'updated_at': utc_now(),
        'ttl': int(time.time()) + (90 * 24 * 60 * 60)
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
        'incident_id': item.get('incident_id'),
        'timestamp': item.get('timestamp'),
        'severity': item.get('severity'),
        'summary': item.get('summary'),
        'action_type': item.get('action_type') or item.get('remediation_action'),
        'target': item.get('target'),
        'source_ip': item.get('source_ip'),
        'destination_ip': item.get('destination_ip'),
        'incident_status': item.get('incident_status'),
        'updated_at': item.get('updated_at')
    }

def save_incident(raw):
    incident = normalize_incident(raw)
    logger.info(f"Saving incident {incident['incident_id']} to DynamoDB")
    table.put_item(Item=sanitize_for_dynamodb(incident))
    return incident

def list_incidents(limit=50):
    response = table.scan(Limit=200)
    items = response.get('Items', [])
    items.sort(key=lambda item: item.get('timestamp', ''), reverse=True)
    return [public_incident(item) for item in items[:limit]]

def isolate_ec2(instance_id):
    """
    Isolates an EC2 instance by attaching a restrictive Security Group
    """
    # Note: In a real scenario, we'd lookup the isolated SG ID from SSM or ENV.
    # Here we mock the behavior or try to find a "Isolation" SG, but for simplicity,
    # we just log it and assume we replaced the SGs.
    logger.info(f"Isolating EC2 instance {instance_id}")

    # Try to describe the instance to get its VPC
    instances = ec2_client.describe_instances(InstanceIds=[instance_id])
    vpc_id = instances['Reservations'][0]['Instances'][0]['VpcId']

    # Check if isolation SG exists
    sgs = ec2_client.describe_security_groups(
        Filters=[
            {'Name': 'vpc-id', 'Values': [vpc_id]},
            {'Name': 'group-name', 'Values': ['Isolation-SG']}
        ]
    )

    sg_id = None
    if not sgs['SecurityGroups']:
        # Create it if it doesn't exist
        response = ec2_client.create_security_group(
            GroupName='Isolation-SG',
            Description='Used to isolate compromised instances',
            VpcId=vpc_id
        )
        sg_id = response['GroupId']
        # Remove all outbound rules (default has allow all)
        ec2_client.revoke_security_group_egress(
            GroupId=sg_id,
            IpPermissions=[
                {
                    'IpProtocol': '-1',
                    'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                }
            ]
        )
    else:
        sg_id = sgs['SecurityGroups'][0]['GroupId']

    # Apply to instance
    ec2_client.modify_instance_attribute(
        InstanceId=instance_id,
        Groups=[sg_id]
    )

    return {"isolated_sg": sg_id}

def revoke_creds(username):
    """
    Deactivates all active access keys for the given IAM user
    """
    logger.info(f"Revoking credentials for user {username}")
    paginator = iam_client.get_paginator('list_access_keys')
    revoked_keys = []

    for page in paginator.paginate(UserName=username):
        for key in page['AccessKeyMetadata']:
            if key['Status'] == 'Active':
                access_key_id = key['AccessKeyId']
                iam_client.update_access_key(
                    UserName=username,
                    AccessKeyId=access_key_id,
                    Status='Inactive'
                )
                revoked_keys.append(access_key_id)
                logger.info(f"Deactivated access key {access_key_id} for user {username}")

    return {"revoked_keys": revoked_keys}

def block_ip(ip_address):
    """
    Mock implementation for blocking IP. In reality, it would update an AWS WAF IPSet or VPC NACL.
    """
    logger.info(f"Blocking IP address {ip_address}")
    # Example logic for WAF: waf_client.update_ip_set(...)
    # For now, we return a mock success
    return {"blocked_ip": ip_address, "method": "mock_waf_ipset_update"}

def update_dynamodb_status(incident_id, action, status):
    """
    Updates the incident status in DynamoDB
    """
    logger.info(f"Updating DynamoDB incident {incident_id} to status {status}")
    try:
        table.update_item(
            Key={'incident_id': incident_id},
            UpdateExpression='SET incident_status = :s, remediation_action = :a, updated_at = :t',
            ExpressionAttributeValues={
                ':s': status,
                ':a': action,
                ':t': utc_now()
            }
        )
    except Exception as e:
        logger.error(f"Failed to update DynamoDB: {str(e)}")
        # In a real environment, you'd want to handle this gracefully
        pass
