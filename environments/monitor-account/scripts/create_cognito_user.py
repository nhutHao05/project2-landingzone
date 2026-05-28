import boto3
import json
import sys

def assume_role(role_arn, session_name="CognitoUserCreator"):
    sts_client = boto3.client('sts')
    assumed_role_object = sts_client.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name
    )
    credentials = assumed_role_object['Credentials']
    return boto3.client(
        'cognito-idp',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'],
        region_name='ap-southeast-1'
    )

import os
import getpass

def main():
    role_arn = os.environ.get("ROLE_ARN", "arn:aws:iam::247448832458:role/OrganizationAccountAccessRole")
    user_pool_id = os.environ.get("USER_POOL_ID", "ap-southeast-1_UYzxlYpH4")
    username = os.environ.get("COGNITO_USERNAME", "admin@soar.local")
    password = os.environ.get("COGNITO_PASSWORD")
    if not password:
        password = getpass.getpass("Enter Cognito password: ")

    print(f"Assuming role {role_arn}...")
    cognito_client = assume_role(role_arn)

    # 1. Create user
    try:
        print(f"Creating user {username}...")
        cognito_client.admin_create_user(
            UserPoolId=user_pool_id,
            Username=username,
            UserAttributes=[
                {'Name': 'email', 'Value': username},
                {'Name': 'email_verified', 'Value': 'true'},
                {'Name': 'name', 'Value': 'Admin'}
            ],
            MessageAction='SUPPRESS' # Do not send email
        )
        print("User created successfully.")
    except Exception as e:
        if "UsernameExistsException" in str(e):
            print("User already exists, continuing...")
        else:
            print(f"Error creating user: {e}")
            sys.exit(1)

    # 2. Set permanent password
    try:
        print(f"Setting password to {password}...")
        cognito_client.admin_set_user_password(
            UserPoolId=user_pool_id,
            Username=username,
            Password=password,
            Permanent=True
        )
        print("Password set successfully.")
    except Exception as e:
        print(f"Error setting password: {e}")
        sys.exit(1)

    # 3. Add user to Admin group
    try:
        print("Adding user to Admin group...")
        cognito_client.admin_add_user_to_group(
            UserPoolId=user_pool_id,
            Username=username,
            GroupName="Admin"
        )
        print("Added to Admin group successfully.")
    except Exception as e:
        print(f"Error adding user to group: {e}")
        sys.exit(1)

    print("=== Cognito User Setup Complete! ===")

if __name__ == "__main__":
    main()
