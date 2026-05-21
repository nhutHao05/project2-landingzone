#!/bin/bash
set -e

echo "Application Access Helper"
echo "========================="
echo ""

AWS_REGION="${AWS_REGION:-ap-southeast-1}"

echo "Layer 1 - OpsDesk Web App"
echo "------------------------"
ALB_DNS=$(cd ../environments/devops-account && terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")

if [ "$ALB_DNS" != "N/A" ]; then
    echo "URL: http://$ALB_DNS/"
    echo ""
    echo "Test connection:"
    echo "  curl -I http://$ALB_DNS/"
    echo "  curl http://$ALB_DNS/api/health.php"
else
    echo "Cannot get ALB DNS. Run terraform apply first."
fi

echo ""
echo "Layer 2 - AI Log Analyzer (Private SSM Access)"
echo "----------------------------------------------"

APP_INSTANCE=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:Role,Values=app" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "None")

if [ "$APP_INSTANCE" != "None" ] && [ -n "$APP_INSTANCE" ]; then
    echo "Instance ID: $APP_INSTANCE"
    echo ""
    echo "Start port forwarding:"
    echo "  aws ssm start-session \\"
    echo "    --target $APP_INSTANCE \\"
    echo "    --document-name AWS-StartPortForwardingSession \\"
    echo "    --parameters '{\"portNumber\":[\"8501\"],\"localPortNumber\":[\"8501\"]}'"
    echo ""
    echo "After port forwarding, access:"
    echo "  http://localhost:8501"
else
    echo "No running app instance found"
    echo "Check instances:"
    echo "  aws ec2 describe-instances --filters \"Name=tag:Role,Values=app\""
fi
