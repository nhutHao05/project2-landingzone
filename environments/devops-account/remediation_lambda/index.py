import json
import boto3
import os
import logging
from datetime import datetime

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

    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }
        
    try:
        body = event.get('body', '{}')
        if isinstance(body, str):
            body = json.loads(body)
            
        incident_id = body.get('incident_id')
        action_type = body.get('action_type')
        target = body.get('target')
        
        if not incident_id or not action_type or not target:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Missing incident_id, action_type, or target'})
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
        else:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': f'Unsupported action_type: {action_type}'})
            }
            
        # Update DynamoDB status
        update_dynamodb_status(incident_id, action_type, 'Resolved')
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': f'Action {action_type} executed successfully on {target}',
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
                ':t': datetime.utcnow().isoformat()
            }
        )
    except Exception as e:
        logger.error(f"Failed to update DynamoDB: {str(e)}")
        # In a real environment, you'd want to handle this gracefully
        pass
