#!/bin/bash
set -e

echo "🔧 Fix CloudWatch Log Groups"
echo "============================="
echo ""

AWS_REGION="ap-southeast-1"

echo "📋 This script will:"
echo "  1. Verify all 9 log groups exist"
echo "  2. Create missing log groups"
echo "  3. Set correct retention policies"
echo "  4. Restart CloudWatch agents on EC2 instances"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ============================================================
# Step 1: Create/Verify Log Groups
# ============================================================
echo ""
echo "📂 Step 1: Creating/Verifying Log Groups..."
echo ""

declare -A LOG_GROUPS=(
    ["/aws/vpc/flowlogs"]=7
    ["/aws/cloudtrail/logs"]=7
    ["/aws/ec2/web-tier/system"]=7
    ["/aws/ec2/web-tier/httpd"]=7
    ["/aws/ec2/web-tier/application"]=14
    ["/aws/ec2/app-tier/system"]=7
    ["/aws/ec2/app-tier/streamlit"]=7
    ["/aws/rds/mysql/error"]=7
    ["/aws/rds/mysql/slowquery"]=14
)

for log_group in "${!LOG_GROUPS[@]}"; do
    retention=${LOG_GROUPS[$log_group]}
    echo -n "  📂 $log_group ... "
    
    # Check if exists
    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" \
        --query "logGroups[?logGroupName=='$log_group']" \
        --output text | grep -q "$log_group"; then
        
        # Update retention
        aws logs put-retention-policy \
            --log-group-name "$log_group" \
            --retention-in-days "$retention" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        echo "✅ EXISTS (retention: $retention days)"
    else
        # Create log group
        aws logs create-log-group \
            --log-group-name "$log_group" \
            --region "$AWS_REGION"
        
        # Set retention
        aws logs put-retention-policy \
            --log-group-name "$log_group" \
            --retention-in-days "$retention" \
            --region "$AWS_REGION"
        
        echo "✅ CREATED (retention: $retention days)"
    fi
done

# ============================================================
# Step 2: Enable RDS CloudWatch Logs Export
# ============================================================
echo ""
echo "💾 Step 2: Enabling RDS CloudWatch Logs Export..."
echo ""

# Find RDS instance
DB_INSTANCE=$(aws rds describe-db-instances \
    --region "$AWS_REGION" \
    --query 'DBInstances[0].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "None")

if [ "$DB_INSTANCE" != "None" ] && [ -n "$DB_INSTANCE" ]; then
    echo "  🗄️ Found RDS instance: $DB_INSTANCE"
    
    # Check current exports
    CURRENT_EXPORTS=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].EnabledCloudwatchLogsExports' \
        --output text)
    
    if echo "$CURRENT_EXPORTS" | grep -q "error" && echo "$CURRENT_EXPORTS" | grep -q "slowquery"; then
        echo "  ✅ RDS logs already enabled"
    else
        echo "  🔧 Enabling error and slowquery logs..."
        aws rds modify-db-instance \
            --db-instance-identifier "$DB_INSTANCE" \
            --cloudwatch-logs-export-configuration \
            '{"EnableLogTypes":["error","slowquery"]}' \
            --region "$AWS_REGION" \
            --apply-immediately
        echo "  ✅ RDS logs enabled (will take effect after reboot)"
    fi
else
    echo "  ⚠️ No RDS instance found"
fi

# ============================================================
# Step 3: Restart CloudWatch Agents
# ============================================================
echo ""
echo "🔄 Step 3: Restarting CloudWatch Agents..."
echo ""

# Find all running instances
INSTANCES=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -n "$INSTANCES" ]; then
    for instance_id in $INSTANCES; do
        # Get instance name
        INSTANCE_NAME=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value' \
            --output text)
        
        echo "  🔄 Restarting CloudWatch Agent on $INSTANCE_NAME ($instance_id)..."
        
        # Restart via SSM
        aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo systemctl restart amazon-cloudwatch-agent"]' \
            --region "$AWS_REGION" \
            --output text > /dev/null
        
        echo "  ✅ Command sent"
    done
else
    echo "  ⚠️ No running instances found"
fi

# ============================================================
# Step 4: Verify
# ============================================================
echo ""
echo "✅ Fix complete! Waiting 30 seconds for agents to restart..."
sleep 30

echo ""
echo "🔍 Running verification..."
./check_logs.sh

echo ""
echo "💡 Tips:"
echo "  - VPC Flow Logs: Wait 5-10 minutes for first logs"
echo "  - CloudTrail: Logs appear when API calls are made"
echo "  - RDS Logs: May need instance reboot to take effect"
echo "  - Web/App Logs: Should appear immediately after agent restart"
echo ""
echo "🎯 Next steps:"
echo "  1. Generate some traffic: curl http://<ALB-DNS>/"
echo "  2. Check logs again: ./check_logs.sh"
echo "  3. Open Streamlit app and run analysis"
