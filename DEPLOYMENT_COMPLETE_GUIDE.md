# 🚀 HƯỚNG DẪN DEPLOY HOÀN CHỈNH - 2 PROJECTS

## 📋 MỤC LỤC
1. [Tổng quan kiến trúc](#tổng-quan-kiến-trúc)
2. [Chuẩn bị môi trường](#chuẩn-bị-môi-trường)
3. [Deploy Infrastructure (Terraform)](#deploy-infrastructure-terraform)
4. [Deploy Database](#deploy-database)
5. [Deploy Applications (Ansible)](#deploy-applications-ansible)
6. [Kiểm tra Log Groups](#kiểm-tra-log-groups)
7. [Truy cập ứng dụng](#truy-cập-ứng-dụng)
8. [Troubleshooting](#troubleshooting)

---

## 🏗️ TỔNG QUAN KIẾN TRÚC

### **Layer 1 - Web Tier (Public Access via ALB)**
- **Ứng dụng**: Web QLSV (PHP)
- **Truy cập**: `http://<ALB-DNS-NAME>/qlsv`
- **Port**: 8080 (internal), 80 (ALB)
- **Log Groups**:
  - `/aws/ec2/web-tier/system` - System logs (messages, secure)
  - `/aws/ec2/web-tier/httpd` - Apache logs (access, error)
  - `/aws/ec2/web-tier/application` - PHP application logs

### **Layer 2 - App Tier (Private - SSM Access Only)**
- **Ứng dụng**: AI Log Analyzer (Streamlit)
- **Truy cập**: SSM Port Forwarding → `http://localhost:8501`
- **Port**: 8501 (Streamlit)
- **Log Groups**:
  - `/aws/ec2/app-tier/system` - System logs
  - `/aws/ec2/app-tier/streamlit` - Streamlit application logs

### **Infrastructure Logs**
- `/aws/vpc/flowlogs` - VPC Flow Logs
- `/aws/cloudtrail/logs` - CloudTrail API logs

### **Database Logs**
- `/aws/rds/mysql/error` - MySQL error logs
- `/aws/rds/mysql/slowquery` - Slow query logs

**TỔNG CỘNG: 9 LOG GROUPS** (giống Streamlit app)

---

## 🔧 CHUẨN BỊ MÔI TRƯỜNG

### 1. Cài đặt công cụ
```bash
# Terraform
terraform --version  # >= 1.0

# Ansible
ansible --version    # >= 2.9

# AWS CLI
aws --version        # >= 2.0

# Python (cho Ansible)
python3 --version    # >= 3.8
```

### 2. Cấu hình AWS Credentials
```bash
# Cấu hình AWS profile
aws configure --profile default

# Kiểm tra
aws sts get-caller-identity --profile default
```

### 3. Cấu hình Telegram Bot (cho AI Alerts)
```bash
# Tạo bot mới với @BotFather trên Telegram
# Lấy BOT_TOKEN và CHAT_ID

# Lưu vào file .env
cd AI_Log_Analysis-Project-1/bedrock-log-analyzer-ui/
cat > .env << EOF
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
TELEGRAM_ALERTS_ENABLED=true
EOF
```

---

## 🏗️ DEPLOY INFRASTRUCTURE (TERRAFORM)

### Bước 1: Bootstrap S3 Backend
```bash
cd bootstrap/
terraform init
terraform plan
terraform apply -auto-approve

# Lưu lại S3 bucket name và DynamoDB table
```

### Bước 2: Deploy Dev Environment
```bash
cd ../environments/dev/

# Kiểm tra variables
cat terraform.tfvars

# Initialize
terraform init

# Plan (xem trước)
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

### Bước 3: Lưu outputs quan trọng
```bash
# ALB DNS Name (cho Web tier)
terraform output alb_dns_name

# DB Endpoint
terraform output db_endpoint

# DB Password (sensitive)
terraform output -raw db_password

# Lưu vào file để dùng sau
terraform output -json > terraform_outputs.json
```

**⏱️ Thời gian**: ~10-15 phút

---

## 💾 DEPLOY DATABASE

### Bước 1: Tạo deployment script
```bash
cd ../../scripts/
mkdir -p database
```

Tạo file `scripts/database/deploy_db.sh`:

```bash
#!/bin/bash
set -e

echo "🗄️ Database Deployment Script"
echo "================================"

# Load DB credentials from Terraform outputs
DB_HOST=$(cd ../../environments/dev && terraform output -raw db_endpoint)
DB_USER="admin"
DB_PASS=$(cd ../../environments/dev && terraform output -raw db_password)
DB_NAME="qlsv_system"

echo "📍 DB Host: $DB_HOST"
echo "👤 DB User: $DB_USER"
echo "🗄️ DB Name: $DB_NAME"

# Kiểm tra kết nối
echo ""
echo "🔍 Testing database connection..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SELECT VERSION();" || {
    echo "❌ Cannot connect to database"
    exit 1
}

echo "✅ Connection successful!"

# Deploy schema
echo ""
echo "📦 Deploying database schema..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" < ../../web-app/database/schema.sql

echo ""
echo "✅ Database deployment complete!"
echo ""
echo "📊 Database Summary:"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "
USE qlsv_system;
SELECT 'Users' as Table_Name, COUNT(*) as Count FROM users
UNION ALL
SELECT 'Students', COUNT(*) FROM students
UNION ALL
SELECT 'Classes', COUNT(*) FROM classes
UNION ALL
SELECT 'Enrollments', COUNT(*) FROM enrollments
UNION ALL
SELECT 'Grades', COUNT(*) FROM grades;
"

echo ""
echo "🔐 Default Accounts:"
echo "  Admin: admin / 123@"
echo "  Lecturers: gv01, gv02, gv03 / 123@"
echo "  Students: sv01-sv10 / 123@"
```

### Bước 2: Chạy deployment
```bash
chmod +x database/deploy_db.sh
./database/deploy_db.sh
```

**⏱️ Thời gian**: ~2-3 phút

---

## 🚀 DEPLOY APPLICATIONS (ANSIBLE)

### Bước 1: Cấu hình Ansible Inventory
```bash
cd ../../ansible/

# Test dynamic inventory
ansible-inventory -i inventory/aws_ec2.yml --list

# Kiểm tra kết nối (qua SSM)
ansible all -i inventory/aws_ec2.yml -m ping
```

### Bước 2: Cập nhật group_vars
```bash
# Lấy DB credentials từ Terraform
DB_HOST=$(cd ../environments/dev && terraform output -raw db_endpoint)
DB_PASS=$(cd ../environments/dev && terraform output -raw db_password)

# Cập nhật ansible/inventory/group_vars/all.yml
cat > inventory/group_vars/all.yml << EOF
---
# Database Configuration
db_host: "$DB_HOST"
db_name: "qlsv_system"
db_user: "admin"
db_password: "$DB_PASS"

# Application Configuration
app_env: "production"
log_level: "INFO"

# Telegram Configuration (cho AI alerts)
telegram_bot_token: "{{ lookup('env', 'TELEGRAM_BOT_TOKEN') }}"
telegram_chat_id: "{{ lookup('env', 'TELEGRAM_CHAT_ID') }}"
telegram_alerts_enabled: "true"
EOF
```

### Bước 3: Deploy tất cả
```bash
# Deploy toàn bộ stack
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml

# Hoặc deploy từng phần:
# 1. EC2 setup + CloudWatch Agent
ansible-playbook -i inventory/aws_ec2.yml playbooks/install_cloudwatch_agent.yml

# 2. Docker
ansible-playbook -i inventory/aws_ec2.yml playbooks/install_docker.yml

# 3. Web App (Layer 1)
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_web_app.yml

# 4. Log Analyzer (Layer 2)
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_log_analyzer.yml
```

**⏱️ Thời gian**: ~10-15 phút

---

## 📊 KIỂM TRA LOG GROUPS

### Script kiểm tra tự động
Tạo file `scripts/check_logs.sh`:

```bash
#!/bin/bash
set -e

echo "📊 CloudWatch Log Groups Status Check"
echo "======================================"
echo ""

AWS_REGION="ap-southeast-1"

# Danh sách log groups theo Streamlit app
LOG_GROUPS=(
    "/aws/vpc/flowlogs"
    "/aws/cloudtrail/logs"
    "/aws/ec2/web-tier/system"
    "/aws/ec2/web-tier/httpd"
    "/aws/ec2/web-tier/application"
    "/aws/ec2/app-tier/system"
    "/aws/ec2/app-tier/streamlit"
    "/aws/rds/mysql/error"
    "/aws/rds/mysql/slowquery"
)

echo "🔍 Checking 9 log groups..."
echo ""

for log_group in "${LOG_GROUPS[@]}"; do
    echo -n "  📂 $log_group ... "
    
    # Kiểm tra log group tồn tại
    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" \
        --query "logGroups[?logGroupName=='$log_group']" \
        --output text | grep -q "$log_group"; then
        
        # Đếm số log streams
        stream_count=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" \
            --query 'length(logStreams)' \
            --output text 2>/dev/null || echo "0")
        
        # Lấy log event gần nhất
        latest_event=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" \
            --max-items 1 \
            --query 'events[0].timestamp' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$latest_event" != "0" ] && [ "$latest_event" != "None" ]; then
            # Convert timestamp to readable format
            latest_time=$(date -d "@$((latest_event / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
            echo "✅ ACTIVE ($stream_count streams, latest: $latest_time)"
        else
            echo "⚠️  EXISTS but NO LOGS YET ($stream_count streams)"
        fi
    else
        echo "❌ NOT FOUND"
    fi
done

echo ""
echo "📈 Summary by Category:"
echo ""

# Infrastructure
echo "🏗️  Infrastructure Logs:"
echo "  - VPC Flow Logs: /aws/vpc/flowlogs"
echo "  - CloudTrail: /aws/cloudtrail/logs"
echo ""

# Web Tier
echo "🌐 Web Tier (Layer 1):"
echo "  - System: /aws/ec2/web-tier/system"
echo "  - HTTP Server: /aws/ec2/web-tier/httpd"
echo "  - Application: /aws/ec2/web-tier/application"
echo ""

# App Tier
echo "🤖 App Tier (Layer 2):"
echo "  - System: /aws/ec2/app-tier/system"
echo "  - Streamlit: /aws/ec2/app-tier/streamlit"
echo ""

# Database
echo "💾 Database:"
echo "  - Error Logs: /aws/rds/mysql/error"
echo "  - Slow Query: /aws/rds/mysql/slowquery"
echo ""

echo "✅ Check complete!"
```

### Chạy kiểm tra
```bash
cd ../scripts/
chmod +x check_logs.sh
./check_logs.sh
```

### Khắc phục nếu log groups trống

**1. VPC Flow Logs & CloudTrail** - Cần thời gian khởi động
```bash
# VPC Flow Logs: đợi 5-10 phút sau khi tạo
# CloudTrail: đợi có API activity

# Test bằng cách tạo traffic
curl http://<ALB-DNS>/qlsv
```

**2. Web Tier Logs** - Kiểm tra CloudWatch Agent
```bash
# SSH vào web instance qua SSM
aws ssm start-session --target <instance-id>

# Kiểm tra CloudWatch Agent
sudo systemctl status amazon-cloudwatch-agent

# Xem config
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Restart nếu cần
sudo systemctl restart amazon-cloudwatch-agent

# Kiểm tra logs
sudo tail -f /var/log/messages
sudo tail -f /var/log/httpd/access_log
```

**3. App Tier Logs** - Kiểm tra Streamlit
```bash
# SSH vào app instance
aws ssm start-session --target <instance-id>

# Kiểm tra container
sudo docker ps

# Xem logs
sudo docker logs <container-id>

# Kiểm tra CloudWatch Agent
sudo systemctl status amazon-cloudwatch-agent
```

**4. RDS Logs** - Enable CloudWatch export
```bash
# Đã enable trong database.tf:
# enabled_cloudwatch_logs_exports = ["error", "slowquery"]

# Kiểm tra RDS parameters
aws rds describe-db-instances \
    --db-instance-identifier <db-identifier> \
    --query 'DBInstances[0].EnabledCloudwatchLogsExports'

# Nếu chưa có, modify:
aws rds modify-db-instance \
    --db-instance-identifier <db-identifier> \
    --cloudwatch-logs-export-configuration \
    '{"EnableLogTypes":["error","slowquery"]}'
```

---

## 🌐 TRUY CẬP ỨNG DỤNG

### Layer 1 - Web QLSV (Public)
```bash
# Lấy ALB DNS
ALB_DNS=$(cd environments/dev && terraform output -raw alb_dns_name)

echo "🌐 Web QLSV: http://$ALB_DNS/qlsv"

# Test
curl -I http://$ALB_DNS/qlsv
```

**Truy cập**: Mở browser → `http://<ALB-DNS>/qlsv`

**Tài khoản mặc định**:
- Admin: `admin` / `123@`
- Giảng viên: `gv01` / `123@`
- Sinh viên: `sv01` / `123@`

### Layer 2 - AI Log Analyzer (Private - SSM)
```bash
# Lấy instance ID của app tier
APP_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Role,Values=app" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

echo "🤖 App Instance: $APP_INSTANCE"

# Port forwarding qua SSM
aws ssm start-session \
    --target $APP_INSTANCE \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8501"],"localPortNumber":["8501"]}'
```

**Truy cập**: Mở browser → `http://localhost:8501`

**Tính năng**:
- Chọn log groups (mặc định: tất cả 9 groups)
- Chọn time range
- AI analysis với Bedrock
- Cross-source correlation
- Telegram alerts

---

## 🔧 TROUBLESHOOTING

### 1. Terraform Errors

**Error: S3 bucket already exists**
```bash
# Xóa state cũ
cd bootstrap/
terraform destroy -auto-approve
rm -rf .terraform terraform.tfstate*
terraform init
terraform apply
```

**Error: Resource already exists**
```bash
# Import resource
terraform import aws_vpc.main <vpc-id>

# Hoặc xóa và tạo lại
terraform destroy -target=aws_vpc.main
terraform apply
```

### 2. Ansible Connection Issues

**Error: Cannot connect to instances**
```bash
# Kiểm tra SSM agent
aws ssm describe-instance-information

# Kiểm tra IAM role
aws ec2 describe-instances \
    --instance-ids <instance-id> \
    --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Restart SSM agent
aws ssm send-command \
    --instance-ids <instance-id> \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo systemctl restart amazon-ssm-agent"]'
```

### 3. Database Connection Issues

**Error: Cannot connect to RDS**
```bash
# Kiểm tra security group
aws ec2 describe-security-groups \
    --group-ids <db-sg-id>

# Kiểm tra từ EC2
aws ssm start-session --target <web-instance-id>
mysql -h <db-endpoint> -u admin -p
```

### 4. CloudWatch Logs Not Appearing

**Kiểm tra IAM permissions**
```bash
# Xem IAM role của EC2
aws iam get-role-policy \
    --role-name <ec2-role-name> \
    --policy-name cloudwatch-agent-policy
```

**Kiểm tra CloudWatch Agent**
```bash
# Trên EC2 instance
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Xem status
sudo systemctl status amazon-cloudwatch-agent

# Xem logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### 5. Telegram Bot Not Working

**Test bot**
```bash
cd AI_Log_Analysis-Project-1/bedrock-log-analyzer-ui/

# Test script
python3 test_telegram.py

# Kiểm tra .env
cat .env

# Test manual
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/sendMessage" \
    -d "chat_id=<CHAT_ID>&text=Test message"
```

---

## 📝 CHECKLIST DEPLOY

### Pre-deployment
- [ ] AWS credentials configured
- [ ] Terraform installed
- [ ] Ansible installed
- [ ] Telegram bot created (optional)

### Infrastructure
- [ ] Bootstrap S3 backend
- [ ] Deploy Terraform (VPC, EC2, RDS, ALB)
- [ ] Verify outputs (ALB DNS, DB endpoint)
- [ ] Check all 9 log groups created

### Database
- [ ] Deploy schema
- [ ] Verify tables created
- [ ] Test connection from EC2

### Applications
- [ ] Deploy CloudWatch Agent
- [ ] Deploy Docker
- [ ] Deploy Web App (Layer 1)
- [ ] Deploy Log Analyzer (Layer 2)

### Verification
- [ ] Web app accessible via ALB
- [ ] Log analyzer accessible via SSM
- [ ] All 9 log groups receiving logs
- [ ] Telegram alerts working
- [ ] Database queries working

---

## 🎯 NEXT STEPS

1. **Security Hardening**
   - Enable HTTPS on ALB
   - Configure WAF rules
   - Enable GuardDuty

2. **Monitoring**
   - Set up CloudWatch Alarms
   - Configure SNS notifications
   - Create dashboards

3. **Backup**
   - Enable RDS automated backups
   - Configure snapshot schedules
   - Test restore procedures

4. **Scaling**
   - Adjust ASG min/max
   - Configure target tracking
   - Load testing

---

## 📞 SUPPORT

Nếu gặp vấn đề:
1. Kiểm tra logs: `./scripts/check_logs.sh`
2. Xem CloudWatch Logs
3. Kiểm tra Security Groups
4. Verify IAM permissions

**Happy Deploying! 🚀**
