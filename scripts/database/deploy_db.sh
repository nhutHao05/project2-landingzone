#!/bin/bash
set -e

echo "OpsDesk database deployment (via SSM Tunnel)"
echo "==========================================="

TERRAFORM_DIR="${TERRAFORM_DIR:-../../environments/devops-account}"
SCHEMA_FILE="${SCHEMA_FILE:-../../web-app/database/schema.sql}"
DB_USER="${DB_USER:-admin}"
DB_NAME="${DB_NAME:-opsdesk}"

echo "Fetching variables from Terraform..."
REAL_DB_HOST=$(cd "$TERRAFORM_DIR" && terraform output -raw db_endpoint | cut -d ':' -f 1)
DB_PASS=$(cd "$TERRAFORM_DIR" && terraform output -raw db_password)

# Lấy 1 EC2 Instance đang chạy để làm cầu nối (Bastion)
echo "Finding active EC2 instance for SSM Tunnel..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" "Name=tag:Role,Values=app" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "❌ Không tìm thấy EC2 instance nào đang chạy để làm cầu nối!"
    exit 1
fi

echo "Opening SSM Port Forwarding Tunnel via $INSTANCE_ID..."
# Mở tunnel ở background trên port 33060
aws ssm start-session --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$REAL_DB_HOST\"],\"portNumber\":[\"3306\"], \"localPortNumber\":[\"33060\"]}" > ssm_tunnel.log 2>&1 &
SSM_PID=$!

# Đợi vài giây để tunnel thiết lập xong
sleep 5

DB_HOST="127.0.0.1"
DB_PORT="33060"

echo "DB mapped host: $DB_HOST:$DB_PORT"
echo "DB user: $DB_USER"
echo "DB name: $DB_NAME"

echo ""
echo "Testing database connection..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT VERSION();" || {
    echo "❌ Cannot connect to database"
    kill $SSM_PID
    exit 1
}

echo "✅ Connection successful"

echo ""
echo "Deploying schema from $SCHEMA_FILE..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" < "$SCHEMA_FILE"

echo ""
echo "Database deployment complete!"
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "
USE ${DB_NAME};
SELECT status, COUNT(*) AS incidents FROM incidents GROUP BY status ORDER BY status;
"

echo "Closing SSM Tunnel..."
kill $SSM_PID
echo "✅ Done!"
