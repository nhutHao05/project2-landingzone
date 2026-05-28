import boto3
import json
import sys
import time
import os

def assume_role(role_arn, session_name="WebPortalDeployer"):
    sts_client = boto3.client('sts')
    assumed_role_object = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name
    )
    credentials = assumed_role_object['Credentials']
    return credentials

def get_clients(credentials):
    s3 = boto3.client(
        's3',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'],
        region_name='ap-southeast-1'
    )
    ssm = boto3.client(
        'ssm',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'],
        region_name='ap-southeast-1'
    )
    return s3, ssm

def main():
    role_arn = "arn:aws:iam::247448832458:role/OrganizationAccountAccessRole"
    bucket_name = "p2-soar-monitor-ansible-ssm-temp"
    instance_id = "i-0f7b421f9d8676ebe"
    web_portal_dir = "d:/Project-2-Landing-Zone/web-portal"

    print("Assuming deployment role...")
    creds = assume_role(role_arn)
    s3, ssm = get_clients(creds)

    files_to_upload = ["index.html", "callback.html", "app.js", "styles.css", "config.json"]

    # 1. Upload files to S3
    for f in files_to_upload:
        local_path = os.path.join(web_portal_dir, f)
        print(f"Uploading {f} to S3 bucket {bucket_name}...")
        s3.upload_file(local_path, bucket_name, f)

    print("All files uploaded to S3 successfully.")

    # 2. Wait for SSM Agent to be active on the instance
    print(f"Checking SSM status for instance {instance_id}...")
    ssm_online = False
    for i in range(15):
        try:
            info = ssm.describe_instance_information(
                Filters=[{'Key': 'InstanceIds', 'Values': [instance_id]}]
            )
            instances = info.get('InstanceInformationList', [])
            if instances and instances[0]['PingStatus'] == 'Online':
                print(f"Instance {instance_id} is ONLINE in SSM.")
                ssm_online = True
                break
            else:
                print(f"Instance is not online yet (ping status: {instances[0]['PingStatus'] if instances else 'not found'}). Waiting 10s...")
        except Exception as e:
            print(f"Error checking SSM: {e}. Waiting 10s...")
        time.sleep(10)

    if not ssm_online:
        print("SSM Agent did not come online in time. Please verify that the EC2 instance is running and has IAM SSM permissions.")
        sys.exit(1)

    # 3. Trigger SSM Command to copy files and reload nginx
    commands = [
        "mkdir -p /var/www/html/portal",
        f"aws s3 cp s3://{bucket_name}/ /var/www/html/portal/ --recursive",
        "chown -R ec2-user:ec2-user /var/www/html/portal",
        "chmod -R 755 /var/www/html/portal",
        "nginx -t && systemctl reload nginx",
        "echo '=== Deployment complete ==='"
    ]

    print("Sending SSM Run Command to deploy files...")
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': commands}
    )

    command_id = response['Command']['CommandId']
    print(f"SSM Command sent. Command ID: {command_id}")

    # 4. Wait for command completion
    print("Waiting for command to complete...")
    for i in range(10):
        time.sleep(5)
        res = ssm.list_command_invocations(
            CommandId=command_id,
            InstanceId=instance_id,
            Details=True
        )
        invocations = res.get('CommandInvocations', [])
        if invocations:
            status = invocations[0]['Status']
            print(f"SSM Command Status: {status}")
            if status in ['Success', 'Failed', 'TimedOut', 'Cancelled']:
                if status == 'Success':
                    print("=== Web Portal deployed successfully to EC2! ===")
                    print("Output details:")
                    for plugin in invocations[0].get('CommandPlugins', []):
                        print(plugin.get('Output'))
                else:
                    print(f"SSM Command failed with status: {status}")
                    for plugin in invocations[0].get('CommandPlugins', []):
                        print(plugin.get('Output'))
                    sys.exit(1)
                break
        else:
            print("Command invocation not found yet...")

if __name__ == "__main__":
    main()
