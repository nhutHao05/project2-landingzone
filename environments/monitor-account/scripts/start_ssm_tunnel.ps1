# start_ssm_tunnel.ps1
$RoleArn = "arn:aws:iam::247448832458:role/OrganizationAccountAccessRole"
$SessionName = "SSM-Tunnel"
$TargetInstance = "i-0f7b421f9d8676ebe"

Write-Host "Assuming role $RoleArn..."
$stsResponse = aws sts assume-role --role-arn $RoleArn --role-session-name $SessionName --output json | ConvertFrom-Json

if (-not $stsResponse) {
    Write-Error "Failed to assume role!"
    exit 1
}

$env:AWS_ACCESS_KEY_ID = $stsResponse.Credentials.AccessKeyId
$env:AWS_SECRET_ACCESS_KEY = $stsResponse.Credentials.SecretAccessKey
$env:AWS_SESSION_TOKEN = $stsResponse.Credentials.SessionToken
$env:AWS_DEFAULT_REGION = "ap-southeast-1"

# Thêm path của Session Manager Plugin vào PATH hiện tại
$env:PATH += ";C:\Program Files\Amazon\SessionManagerPlugin\bin"

aws ssm start-session `
  --target $TargetInstance `
  --document-name AWS-StartPortForwardingSession `
  --parameters '{\"portNumber\":[\"80\"],\"localPortNumber\":[\"8080\"]}' `
  --region ap-southeast-1
