# 🚀 Hướng Dẫn Deploy Lên AWS - Chi Tiết

## 📋 Mục Lục
1. [Chuẩn Bị](#chuẩn-bị)
2. [Bước 1: Setup AWS Credentials](#bước-1-setup-aws-credentials)
3. [Bước 2: Deploy Infrastructure với Terraform](#bước-2-deploy-infrastructure-với-terraform)
4. [Bước 3: Khởi Tạo Database](#bước-3-khởi-tạo-database)
5. [Bước 4: Deploy Applications với Ansible](#bước-4-deploy-applications-với-ansible)
6. [Bước 5: Truy Cập Hệ Thống](#bước-5-truy-cập-hệ-thống)
7. [Bước 6: Test & Verify](#bước-6-test--verify)
8. [Troubleshooting](#troubleshooting)

---

## Chuẩn Bị

### Yêu Cầu Hệ Thống

- **AWS Account** với quyền:
  - EC2, VPC, RDS, ALB, CloudWatch, CloudTrail
  - IAM (tạo roles, policies)
  - Bedrock (access Claude models)
- **Tools cần cài:**
  - Terraform >= 1.5
  - Ansible >= 2.14
  - AWS CLI >= 2.0
  - Python >= 3.9
  - Session Manager Plugin

### Cài Đặt Tools

#### Windows với WSL (Khuyên Dùng)

```bash
# Mở WSL terminal (Ubuntu)
wsl

# Update package list
sudo apt update

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Ansible
sudo apt install ansible -y

# MySQL Client
sudo apt install mysql-client -y

# Session Manager Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb

# Verify installations
aws --version
terraform --version
ansible --version
mysql --version
session-manager-plugin --version
```

#### Windows (PowerShell - Alternative)

```powershell
# AWS CLI
winget install Amazon.AWSCLI

# Terraform
winget install Hashicorp.Terraform

# Ansible (qua WSL hoặc Python)
pip install ansible

# Session Manager Plugin
# Download từ: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

#### macOS

```bash
# Homebrew
brew install awscli terraform ansible

# Session Manager Plugin
brew install --cask session-manager-plugin
```

#### Linux (Ubuntu/Debian)

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Ansible
sudo apt install ansible

# Session Manager Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

---

## Bước 1: Setup AWS Credentials

### 1.1. Mở WSL Terminal

```bash
# Mở WSL từ Windows
wsl

# Hoặc mở Ubuntu app từ Start Menu
```

### 1.2. Tạo IAM User (nếu chưa có)

```bash
# Login vào AWS Console
# IAM → Users → Create User
# Attach policies:
#   - AdministratorAccess (hoặc custom policy với quyền cần thiết)
# Security credentials → Create access key
```

### 1.3. Configure AWS CLI trong WSL

```bash
# Trong WSL terminal
aws configure

# Nhập thông tin:
AWS Access Key ID: YOUR_ACCESS_KEY
AWS Secret Access Key: YOUR_SECRET_KEY
Default region name: ap-southeast-1
Default output format: json
```

⚠️ **Lưu ý cho WSL:**
- AWS credentials sẽ được lưu trong `~/.aws/` trong WSL
- Không dùng chung credentials với Windows PowerShell
- Mỗi WSL distribution có credentials riêng

### 1.4. Verify AWS Access

```bash
# Test connection
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

### 1.5. Enable Bedrock Model Access

```bash
# Mở AWS Console → Bedrock → Model access
# Request access cho:
#   - Claude 3.5 Sonnet (us.anthropic.claude-3-5-sonnet-20240620-v1:0)
#   - Claude 3 Haiku (anthropic.claude-3-haiku-20240307-v1:0)

# Verify
aws bedrock list-foundation-models --region ap-southeast-1 | grep claude
```

---

## Bước 2: Deploy Infrastructure với Terraform

### 2.1. Clone Repository trong WSL

```bash
# Trong WSL terminal
cd ~

# Clone repository
git clone <your-repo-url>
cd terraform-for-project1

# Hoặc nếu code đã có trên Windows, access qua /mnt/
cd /mnt/d/terraform-for-project1
```

⚠️ **Lưu ý về đường dẫn WSL:**
- Windows drives được mount tại `/mnt/` (ví dụ: `D:\` → `/mnt/d/`)
- Khuyên dùng: Clone code trong WSL filesystem (`~`) để performance tốt hơn
- Tránh chạy Terraform từ `/mnt/` vì có thể chậm

### 2.2. Di Chuyển Vào Thư Mục Environment

```bash
cd environments/dev
```

### 2.3. Set Environment Variables (QUAN TRỌNG!)

```bash
# Set Database Password (KHÔNG commit vào git)
export TF_VAR_db_password="YOUR_SECURE_PASSWORD_HERE"

# Set Telegram Credentials
export TF_VAR_telegram_bot_token="YOUR_TELEGRAM_BOT_TOKEN"
export TF_VAR_telegram_chat_id="YOUR_TELEGRAM_CHAT_ID"

# Verify variables đã được set
echo "DB Password: $TF_VAR_db_password"
echo "Telegram Bot: $TF_VAR_telegram_bot_token"
echo "Telegram Chat: $TF_VAR_telegram_chat_id"
```

⚠️ **LƯU Ý QUAN TRỌNG:**
- **KHÔNG** tạo file `terraform.tfvars` chứa password
- **KHÔNG** commit password vào git
- Dùng environment variables để bảo mật thông tin nhạy cảm
- Mỗi lần mở WSL terminal mới phải export lại các biến này
- Có thể thêm vào `~/.bashrc` hoặc `~/.zshrc` để tự động load (không khuyến khích cho production)

### 2.4. Initialize Terraform

```bash
# Initialize providers và download modules
terraform init

# Expected output:
# Terraform has been successfully initialized!
```

### 2.5. Validate Configuration

```bash
# Kiểm tra syntax
terraform validate

# Expected output:
# Success! The configuration is valid.
```

### 2.6. Plan Infrastructure

```bash
# Review changes trước khi deploy
terraform plan

# Kiểm tra output sẽ tạo:
# - VPC với 3 AZs (public, private, db subnets)
# - Internet Gateway + NAT Gateway (nếu enable)
# - Security Groups (ALB, Web, App, DB, SSM)
# - EC2 instances (Web tier, App tier)
# - RDS MySQL database
# - Application Load Balancer
# - CloudWatch Log Groups
# - CloudTrail
# - IAM Roles & Policies
# - VPC Endpoints (SSM, S3)
# - S3 Buckets (CloudTrail, Ansible temp)

# Expected: Plan: 94 to add, 0 to change, 0 to destroy
```

### 2.7. Apply Infrastructure

```bash
# Deploy infrastructure
terraform apply

# Review plan một lần nữa
# Type 'yes' when prompted

# ⏱️ Thời gian: ~10-15 phút
# - VPC & Networking: ~2 phút
# - RDS Database: ~5-7 phút (lâu nhất)
# - EC2 Instances: ~2-3 phút
# - Load Balancer: ~2 phút
```

### 2.8. Verify Deployment

```bash
# Check Terraform state
terraform state list

# Should show ~94 resources created
```

### 2.9. Save Important Outputs

```bash
# Lưu outputs vào file
terraform output > ../../deployment_outputs.txt

# Xem tất cả outputs
terraform output

# Lưu từng output quan trọng vào biến
export ALB_DNS=$(terraform output -raw alb_dns_name)
export VPC_ID=$(terraform output -raw vpc_id)
export WEB_INSTANCE_ID=$(terraform output -json ec2_instance_ids | jq -r '.["web-server"]')
export APP_INSTANCE_ID=$(terraform output -json ec2_instance_ids | jq -r '.["l2-node-1"]')
export DB_ENDPOINT=$(terraform output -raw db_endpoint)

# Hiển thị thông tin quan trọng
echo "=========================================="
echo "🎉 DEPLOYMENT SUCCESSFUL!"
echo "=========================================="
echo "ALB DNS: $ALB_DNS"
echo "VPC ID: $VPC_ID"
echo "Web Instance: $WEB_INSTANCE_ID"
echo "App Instance: $APP_INSTANCE_ID"
echo "DB Endpoint: $DB_ENDPOINT"
echo "=========================================="
echo ""
echo "📝 Outputs đã được lưu vào: deployment_outputs.txt"
echo ""
```

### 2.10. Verify Resources in AWS Console

```bash
# Mở AWS Console và kiểm tra:
# 1. EC2 → Instances → Thấy 2 instances (web, app) đang running
# 2. RDS → Databases → Thấy database đang available
# 3. VPC → Your VPCs → Thấy VPC mới
# 4. EC2 → Load Balancers → Thấy ALB đang active
# 5. CloudWatch → Log groups → Thấy các log groups

# Hoặc dùng CLI
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=project1" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

---

## Bước 3: Khởi Tạo Database

⚠️ **QUAN TRỌNG:** Phải khởi tạo database trước khi deploy applications!

### 3.1. Lấy Thông Tin Database

```bash
# Lấy RDS endpoint từ Terraform output
cd environments/dev
export DB_ENDPOINT=$(terraform output -raw db_endpoint)
export DB_PASSWORD=$(echo $TF_VAR_db_password)

echo "Database Endpoint: $DB_ENDPOINT"
echo "Database Password: $DB_PASSWORD"
```

### 3.2. Cài Đặt MySQL Client (nếu chưa có)

MySQL client đã được cài trong bước setup tools. Verify:

```bash
mysql --version
# Expected: mysql  Ver 8.0.x for Linux
```

Nếu chưa có:

```bash
sudo apt update
sudo apt install mysql-client -y
```

### 3.3. Test Kết Nối Database

```bash
# Test connection
mysql -h $DB_ENDPOINT -P 3306 -u admin -p

# Nhập password khi được hỏi
# Expected: MySQL prompt "mysql>"
```

⚠️ **Nếu không kết nối được:**
1. Kiểm tra Security Group của RDS có cho phép kết nối từ IP của bạn
2. Kiểm tra RDS có publicly accessible = true (trong dev environment)
3. Kiểm tra password đúng chưa

### 3.4. Import Database Schema

```bash
# Di chuyển về root project
cd ../..

# Import database cho Web QLSV
mysql -h $DB_ENDPOINT -P 3306 -u admin -p < web-app/database/schema.sql

# Expected output:
# (Không có lỗi, import thành công)
```

### 3.5. Verify Database

```bash
# Connect và kiểm tra
mysql -h $DB_ENDPOINT -P 3306 -u admin -p

# Trong MySQL prompt:
mysql> SHOW DATABASES;
# Expected: Thấy database 'qlsv_system'

mysql> USE qlsv_system;
mysql> SHOW TABLES;
# Expected: Thấy 6 tables (roles, users, classes, students, enrollments, grades)

mysql> SELECT COUNT(*) FROM users;
# Expected: 14 users (1 admin + 3 lecturers + 10 students)

mysql> SELECT username, role_id FROM users LIMIT 5;
# Expected: Thấy admin, gv01, gv02, sv01, sv02...

mysql> EXIT;
```

### 3.6. Database Schema Summary

Database `qlsv_system` đã được tạo với:

| Table | Description | Records |
|-------|-------------|---------|
| roles | Vai trò (Admin, Lecturer, Student) | 3 |
| users | Tài khoản người dùng | 14 |
| classes | Lớp học | 5 |
| students | Thông tin sinh viên | 10 |
| enrollments | Đăng ký môn học | 5 |
| grades | Điểm số | 4 |

**Tài khoản mặc định** (password: `123@`):
- Admin: `admin`
- Lecturers: `gv01`, `gv02`, `gv03`
- Students: `sv01` đến `sv10`

---

## Bước 4: Deploy Applications với Ansible

### 4.1. Chuẩn Bị Ansible Inventory

```bash
cd ansible

# Verify AWS EC2 dynamic inventory
ansible-inventory -i inventory/aws_ec2.yml --list

# Expected: Danh sách EC2 instances với tags
```

### 4.2. Set Environment Variables cho Ansible

```bash
# Database credentials (đã có từ Terraform)
export DB_PASSWORD="$TF_VAR_db_password"

# Telegram credentials (đã có từ Terraform)
export TELEGRAM_BOT_TOKEN="$TF_VAR_telegram_bot_token"
export TELEGRAM_CHAT_ID="$TF_VAR_telegram_chat_id"

# Verify
echo "DB Password: $DB_PASSWORD"
echo "Telegram Bot: $TELEGRAM_BOT_TOKEN"
echo "Telegram Chat: $TELEGRAM_CHAT_ID"
```

### 4.3. Test Ansible Connectivity

```bash
# Test SSM connectivity (không cần SSH keys)
ansible all -i inventory/aws_ec2.yml -m ping

# Expected output:
# web-server | SUCCESS => {"ping": "pong"}
# app-server | SUCCESS => {"ping": "pong"}
```

### 4.4. Deploy All Applications

```bash
# Deploy toàn bộ stack
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml

# ⏱️ Thời gian: ~5-10 phút

# Playbook sẽ:
# 1. Install Docker trên cả 2 EC2 instances
# 2. Install CloudWatch Agent
# 3. Deploy Web Application (PHP QLSV) - Port 8080
# 4. Deploy Log Analyzer (Streamlit + Bedrock) - Port 8501
# 5. Deploy Versus Incident (Alert Gateway) - Port 3000
# 6. Configure log collection to CloudWatch
```

### 4.5. Deploy Từng Application Riêng Lẻ (Optional)

Nếu muốn deploy từng app riêng:

```bash
# Deploy Web App only
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_web_app.yml

# Deploy Log Analyzer only
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_log_analyzer.yml

# Deploy Versus Incident only
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_versus_incident.yml

# Install Docker only
ansible-playbook -i inventory/aws_ec2.yml playbooks/install_docker.yml

# Install CloudWatch Agent only
ansible-playbook -i inventory/aws_ec2.yml playbooks/install_cloudwatch_agent.yml
```

### 4.6. Verify Deployment

```bash
# Check playbook output
# Tất cả tasks phải có status: ok hoặc changed
# Không có failed tasks
```

### 4.7. Verify Applications Running on EC2

```bash
# Get instance IDs
cd ../environments/dev
export WEB_INSTANCE_ID=$(terraform output -json ec2_instance_ids | jq -r '.["web-server"]')
export APP_INSTANCE_ID=$(terraform output -json ec2_instance_ids | jq -r '.["l2-node-1"]')

# Check Web Server containers
aws ssm start-session --target $WEB_INSTANCE_ID
# Inside instance:
docker ps
# Expected: Container 'student-management-app' running on port 8080

# Check App Server containers
aws ssm start-session --target $APP_INSTANCE_ID
# Inside instance:
docker ps
# Expected: 
#   - Container 'bedrock-log-analyzer' running on port 8501
#   - Container 'versus-incident' running on port 3000
```

---

## Bước 5: Truy Cập Hệ Thống

### 5.1. Truy Cập Web Application (Layer 1 - Public)

```bash
# Mở browser từ WSL (sẽ mở browser trên Windows)
explorer.exe "http://${ALB_DNS}:8080"

# Hoặc dùng wslview (nếu đã cài wslu)
wslview "http://${ALB_DNS}:8080"

# Hoặc copy URL và paste vào browser trên Windows
echo "http://${ALB_DNS}:8080"
```

### 5.2. Login Web Application

```bash
# Copy URL và mở trên Windows browser
echo "Web App URL: http://${ALB_DNS}:8080"

# Trang login sẽ hiện ra
# Test với tài khoản:
```

**Tài khoản test:**

| Vai trò | Username | Password | Chức năng |
|---------|----------|----------|-----------|
| Admin | admin | 123@ | Quản lý toàn bộ hệ thống |
| Giảng viên | gv01 | 123@ | Xem lớp, chấm điểm |
| Sinh viên | sv01 | 123@ | Xem điểm, thông tin |

### 5.3. Truy Cập Log Analyzer (Layer 2 - Private via SSM)

⚠️ **Layer 2 chỉ accessible qua AWS SSM Port Forwarding (Zero Trust)**

```bash
# Get App Server instance ID
export APP_INSTANCE_ID=$(terraform output -raw app_instance_id)

# Start SSM Port Forwarding
aws ssm start-session \
  --target $APP_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8501"]}'

# Output:
# Starting session with SessionId: your-session-id
# Port 8501 opened for sessionId your-session-id.
# Waiting for connections...

# Mở browser (terminal mới - vẫn trong WSL):
explorer.exe http://localhost:8501
# hoặc
wslview http://localhost:8501
# hoặc mở browser Windows và truy cập: http://localhost:8501
```

**Lưu ý:** Giữ terminal SSM chạy, đóng terminal = mất kết nối.

### 5.4. Truy Cập Versus Incident (Layer 2 - Private via SSM)

```bash
# Start SSM Port Forwarding cho Versus Incident
aws ssm start-session \
  --target $APP_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# Mở browser (terminal mới):
explorer.exe http://localhost:3000
```

### 5.5. Script Tự Động (Khuyên Dùng)

```bash
# Sử dụng script có sẵn
cd scripts

# Make scripts executable
chmod +x ssm-connect-layer2.sh ssm-connect-all.sh

# Connect to Layer 2
./ssm-connect-layer2.sh

# Hoặc connect to all instances
./ssm-connect-all.sh
```

⚠️ **Lưu ý WSL Port Forwarding:**
- Port forwarding từ WSL tự động accessible từ Windows
- Truy cập `localhost:8501` từ Windows browser sẽ kết nối đến WSL
- Nếu không truy cập được, check Windows Firewall

---

## Bước 6: Test & Verify

### 6.1. Test Web Application Login

```bash
# Test login với admin account
curl -X POST "http://${ALB_DNS}:8080/api/login.php" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"123@","role":"ADMIN"}'

# Expected: JSON response với user data
# {"ok":true,"message":"Đăng nhập thành công","user":{...},"redirect":"/admin/dashboard.php"}

# Test login với student account
curl -X POST "http://${ALB_DNS}:8080/api/login.php" \
  -H "Content-Type: application/json" \
  -d '{"username":"sv01","password":"123@","role":"STUDENT"}'

# Expected: JSON response với student data
```

### 6.2. Test Database Connection từ Web App

```bash
# Check database connection trong container
aws ssm start-session --target $WEB_INSTANCE_ID

# Inside instance:
docker exec student-management-app cat /var/www/html/.env
# Expected: Thấy DB_HOST, DB_USER, DB_PASS, DB_NAME

# Test PHP connection
docker exec student-management-app php -r "
\$mysqli = new mysqli(
  getenv('DB_HOST'),
  getenv('DB_USER'),
  getenv('DB_PASS'),
  getenv('DB_NAME')
);
if (\$mysqli->connect_error) {
  die('Connection failed: ' . \$mysqli->connect_error);
}
echo 'Connected successfully to database: ' . getenv('DB_NAME') . PHP_EOL;
\$mysqli->close();
"

# Expected: "Connected successfully to database: qlsv_system"
```

### 6.3. Test Log Collection

```bash
# Check CloudWatch Logs
aws logs describe-log-groups --region ap-southeast-1

# Expected log groups:
# - /aws/vpc/flowlogs
# - /aws/cloudtrail/logs
# - /aws/ec2/application
# - /aws/rds/mysql/error
```

### 6.4. Generate Test Logs

```bash
# Generate some activity logs
for i in {1..10}; do
  curl -X POST "http://${ALB_DNS}:8080/api/login.php" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"123@","role":"ADMIN"}'
  sleep 1
done

# Generate failed login attempts
for i in {1..5}; do
  curl -X POST "http://${ALB_DNS}:8080/api/login.php" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"wrongpass","role":"ADMIN"}'
  sleep 1
done
```

### 6.5. Run Attack Simulation (Optional)

```bash
# Nếu có script attack simulation
cd dos_test

# Run locust attack
locust -f locustfile.py --host="http://${ALB_DNS}:8080" --headless -u 10 -r 2 -t 60s

# Hoặc dùng script attack login
python attack_login.py --target "http://${ALB_DNS}:8080" --duration 60
```

### 6.6. Analyze Logs in UI

1. **Mở Log Analyzer UI**: http://localhost:8501 (qua SSM)
2. **Configure Settings:**
   - Log Sources: Chọn tất cả (VPC Flow, CloudTrail, Application, RDS)
   - Time Range: Last 1 hour
   - AI Enhancement: Enabled
3. **Click "🚀 Analyze Logs"**
4. **Chờ kết quả** (~30-60 giây)
5. **Kiểm tra Telegram** - Bạn sẽ nhận alert!

### 6.7. Verify Telegram Alert

```bash
# Test Telegram integration
cd AI_Log_Analysis-Project-1/bedrock-log-analyzer-ui
python test_telegram.py

# Expected:
# ✅ Test alert sent successfully!
# Check your Telegram app for the message.
```

---

### 6.8. Check All Services Status

```bash
# Web Server
aws ssm start-session --target $WEB_INSTANCE_ID
docker ps
docker logs student-management-app --tail 50

# App Server
aws ssm start-session --target $APP_INSTANCE_ID
docker ps
docker logs bedrock-log-analyzer --tail 50
docker logs versus-incident --tail 50

# CloudWatch Logs
aws logs tail /aws/ec2/web-tier/application --follow
aws logs tail /aws/ec2/app-tier/streamlit --follow
```

---

## Troubleshooting

### Issue 1: Database Connection Failed

**Lỗi:** `Cannot connect to database` hoặc `Access denied`

**Giải pháp:**
```bash
# 1. Kiểm tra RDS Security Group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*db*" \
  --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions]'

# 2. Kiểm tra RDS endpoint
cd environments/dev
terraform output db_endpoint

# 3. Test connection từ EC2
aws ssm start-session --target $WEB_INSTANCE_ID
mysql -h $DB_ENDPOINT -u admin -p

# 4. Kiểm tra .env trong container
docker exec student-management-app cat /var/www/html/.env

# 5. Kiểm tra database tồn tại
mysql -h $DB_ENDPOINT -u admin -p -e "SHOW DATABASES;"
```

### Issue 2: Web App Shows Database Error

**Lỗi:** `Database connection error` trên web page

**Giải pháp:**
```bash
# 1. Kiểm tra container logs
docker logs student-management-app --tail 100

# 2. Kiểm tra PHP error logs
docker exec student-management-app tail -f /var/log/apache2/error.log

# 3. Test PHP database connection
docker exec student-management-app php -r "
\$host = getenv('DB_HOST');
\$user = getenv('DB_USER');
\$pass = getenv('DB_PASS');
\$db = getenv('DB_NAME');
echo \"Connecting to: \$host as \$user to database \$db\n\";
\$mysqli = new mysqli(\$host, \$user, \$pass, \$db);
if (\$mysqli->connect_error) {
  die('Error: ' . \$mysqli->connect_error);
}
echo 'Success!\n';
"

# 4. Restart container
docker restart student-management-app
```

### Issue 3: Terraform Apply Failed

**Lỗi:** `Error creating EC2 Instance: UnauthorizedOperation`

**Giải pháp:**
```bash
# Check IAM permissions
aws iam get-user

# Ensure user has EC2 permissions
# Add policy: AmazonEC2FullAccess
```

---

### Issue 4: Ansible Cannot Connect

**Lỗi:** `Failed to connect to the host via ssm`

**Giải pháp:**
```bash
# Install Session Manager Plugin
# See: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

# Verify installation
session-manager-plugin --version

# Check instance has SSM agent
aws ssm describe-instance-information
```

---

### Issue 5: Cannot Access Layer 2 UI

**Lỗi:** `Connection refused on localhost:8501`

**Giải pháp:**
```bash
# Ensure SSM port forwarding is running
aws ssm start-session \
  --target $(cd environments/dev && terraform output -raw app_instance_id) \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8501"]}'

# Check Streamlit is running on instance
aws ssm start-session --target $APP_INSTANCE_ID
# Inside instance:
docker ps | grep streamlit
```

---

### Issue 6: Logs Not Appearing in CloudWatch

**Lỗi:** No logs in CloudWatch Log Groups

**Giải pháp:**
```bash
# SSH into instance via SSM
aws ssm start-session --target $APP_INSTANCE_ID

# Check CloudWatch Agent status
sudo systemctl status amazon-cloudwatch-agent

# Restart agent
sudo systemctl restart amazon-cloudwatch-agent

# Check logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

---

### Issue 7: Bedrock API Errors

**Lỗi:** `AccessDeniedException: Could not access model`

**Giải pháp:**
```bash
# Enable model access in AWS Console
# Bedrock → Model access → Request model access
# Select: Claude 3.5 Sonnet, Claude 3 Haiku

# Verify
aws bedrock list-foundation-models --region ap-southeast-1 | grep claude
```

---

### Issue 8: Telegram Alerts Not Sending

**Lỗi:** `Telegram alert not sent (check configuration)`

**Giải pháp:**
```bash
# Check environment variables
echo $TELEGRAM_BOT_TOKEN
echo $TELEGRAM_CHAT_ID

# Test bot manually
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=Test from CLI"

# Check .env file on instance
aws ssm start-session --target $APP_INSTANCE_ID
cat /home/ubuntu/bedrock-log-analyzer/.env
```

---

## 🎯 Deployment Checklist

### Pre-Deployment (WSL Setup)
- [ ] WSL installed và running (Ubuntu recommended)
- [ ] AWS CLI installed trong WSL
- [ ] Terraform installed trong WSL (>= 1.5)
- [ ] Ansible installed trong WSL (>= 2.14)
- [ ] MySQL Client installed trong WSL
- [ ] Session Manager Plugin installed trong WSL
- [ ] Git configured trong WSL
- [ ] Bedrock model access enabled (Claude 3.5 Sonnet, Claude 3 Haiku)
- [ ] AWS credentials có đủ quyền (EC2, VPC, RDS, IAM, Bedrock, CloudWatch)

### Terraform Deployment (trong WSL)
- [ ] Clone repository hoặc cd vào `/mnt/d/terraform-for-project1`
- [ ] `cd environments/dev`
- [ ] Export `TF_VAR_db_password` (KHÔNG commit vào git)
- [ ] Export `TF_VAR_telegram_bot_token`
- [ ] Export `TF_VAR_telegram_chat_id`
- [ ] `terraform init` thành công
- [ ] `terraform validate` thành công
- [ ] `terraform plan` - review ~94 resources
- [ ] `terraform apply` - type 'yes'
- [ ] Chờ ~10-15 phút
- [ ] `terraform output` - lưu outputs
- [ ] Verify resources trong AWS Console (từ Windows browser)

### Database Initialization
- [ ] Lấy RDS endpoint từ Terraform output
- [ ] Test connection: `mysql -h $DB_ENDPOINT -u admin -p`
- [ ] Import schema: `mysql -h $DB_ENDPOINT -u admin -p < web-app/database/schema.sql`
- [ ] Verify: `SHOW DATABASES;` thấy `qlsv_system`
- [ ] Verify: `USE qlsv_system; SHOW TABLES;` thấy 6 tables
- [ ] Verify: `SELECT COUNT(*) FROM users;` thấy 14 users

### Ansible Deployment
- [ ] `cd ansible`
- [ ] Export `DB_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
- [ ] `ansible-inventory -i inventory/aws_ec2.yml --list` - thấy instances
- [ ] `ansible all -i inventory/aws_ec2.yml -m ping` - all SUCCESS
- [ ] `ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml`
- [ ] Chờ ~5-10 phút
- [ ] Không có failed tasks

### Verification (WSL + Windows)
- [ ] Web App accessible từ Windows browser: `http://${ALB_DNS}:8080`
- [ ] Login thành công với admin/123@
- [ ] Database connection working (không có error)
- [ ] SSM port forwarding working từ WSL
- [ ] Log Analyzer UI accessible từ Windows browser: `http://localhost:8501`
- [ ] Versus Incident accessible từ Windows browser: `http://localhost:3000`
- [ ] CloudWatch logs collecting
- [ ] Telegram alerts working
- [ ] All Docker containers running trên EC2

### Post-Deployment
- [ ] Đổi password mặc định (123@)
- [ ] Documentation reviewed
- [ ] Outputs saved to `deployment_outputs.txt`
- [ ] Team notified
- [ ] Monitoring setup verified
- [ ] Backup strategy configured

---

## 📝 Quick Reference Commands

### Terraform
```bash
# Initialize
cd environments/dev
export TF_VAR_db_password="YourPassword"
terraform init

# Deploy
terraform plan
terraform apply

# Get outputs
terraform output
terraform output -raw alb_dns_name

# Destroy
terraform destroy
```

### Ansible
```bash
# Test connectivity
cd ansible
ansible all -i inventory/aws_ec2.yml -m ping

# Deploy all
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml

# Deploy specific
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_web_app.yml
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_log_analyzer.yml
```

### SSM Access
```bash
# Port forward to Layer 2
aws ssm start-session \
  --target $APP_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["80"],"localPortNumber":["8501"]}'

# Shell access
aws ssm start-session --target $APP_INSTANCE_ID
```

### CloudWatch Logs
```bash
# List log groups
aws logs describe-log-groups

# Tail logs
aws logs tail /aws/ec2/web-tier/application --follow

# Get recent logs
aws logs tail /aws/ec2/app-tier/streamlit --since 1h
```

---

## 📝 Quick Reference Commands

### Terraform
```bash
# Initialize
cd environments/dev
export TF_VAR_db_password="YourPassword"
export TF_VAR_telegram_bot_token="YourToken"
export TF_VAR_telegram_chat_id="YourChatID"
terraform init

# Deploy
terraform plan
terraform apply

# Get outputs
terraform output
terraform output -raw alb_dns_name
terraform output -raw db_endpoint

# Destroy
terraform destroy
```

### Database
```bash
# Connect to RDS
mysql -h $DB_ENDPOINT -P 3306 -u admin -p

# Import schema
mysql -h $DB_ENDPOINT -P 3306 -u admin -p < web-app/database/schema.sql

# Verify
mysql -h $DB_ENDPOINT -P 3306 -u admin -p -e "USE qlsv_system; SHOW TABLES;"
```

### Ansible
```bash
# Test connectivity
cd ansible
ansible all -i inventory/aws_ec2.yml -m ping

# Deploy all
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml

# Deploy specific
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_web_app.yml
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_log_analyzer.yml
ansible-playbook -i inventory/aws_ec2.yml playbooks/deploy_versus_incident.yml
```

### SSM Access
```bash
# Port forward to Log Analyzer (Layer 2)
aws ssm start-session \
  --target $APP_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8501"],"localPortNumber":["8501"]}'

# Port forward to Versus Incident (Layer 2)
aws ssm start-session \
  --target $APP_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'

# Shell access
aws ssm start-session --target $WEB_INSTANCE_ID
aws ssm start-session --target $APP_INSTANCE_ID
```

### Docker Commands (SSH vào EC2 từ WSL)
```bash
# List containers
docker ps

# View logs
docker logs student-management-app --tail 100 -f
docker logs bedrock-log-analyzer --tail 100 -f
docker logs versus-incident --tail 100 -f

# Restart container
docker restart student-management-app

# Check .env
docker exec student-management-app cat /var/www/html/.env
```

### CloudWatch Logs
```bash
# List log groups
aws logs describe-log-groups

# Tail logs
aws logs tail /aws/ec2/web-tier/application --follow
aws logs tail /aws/ec2/app-tier/streamlit --follow

# Get recent logs
aws logs tail /aws/vpc/flowlogs --since 1h
```

---

## 📊 Cost Monitoring

```bash
# Check current costs
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=SERVICE

# Set billing alerts
aws cloudwatch put-metric-alarm \
  --alarm-name billing-alarm \
  --alarm-description "Alert when bill exceeds $100" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```

---

## 🧹 Cleanup (Xóa Toàn Bộ)

### Cách 1: Terraform Destroy (Khuyên Dùng)

```bash
# Di chuyển vào thư mục terraform
cd environments/dev

# Đảm bảo environment variables vẫn còn
export TF_VAR_db_password="YOUR_SECURE_PASSWORD_HERE"

# Xem resources sẽ bị xóa
terraform plan -destroy

# Xóa toàn bộ infrastructure
terraform destroy

# Type 'yes' when prompted
# ⏱️ Thời gian: ~5-10 phút
```

### Cách 2: Xóa Từng Phần (Nếu Destroy Bị Lỗi)

```bash
# Xóa EC2 instances trước
terraform destroy -target=aws_instance.web
terraform destroy -target=aws_instance.app

# Xóa RDS database
terraform destroy -target=aws_db_instance.main

# Xóa Load Balancer
terraform destroy -target=aws_lb.main

# Xóa toàn bộ còn lại
terraform destroy
```

### Verify Cleanup

```bash
# Kiểm tra không còn resources
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=project1" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table

# Kiểm tra VPC
aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=project1" \
  --query 'Vpcs[*].[VpcId,State]' \
  --output table

# Kiểm tra RDS
aws rds describe-db-instances \
  --query 'DBInstances[?contains(DBInstanceIdentifier, `p1-dev`)].DBInstanceIdentifier'

# Expected: Tất cả đều empty hoặc terminated
```

### Manual Cleanup (Nếu Cần)

```bash
# Xóa CloudWatch Log Groups (nếu còn)
aws logs describe-log-groups --query 'logGroups[*].logGroupName' | \
  grep -E '/aws/(ec2|rds|vpc|cloudtrail)' | \
  xargs -I {} aws logs delete-log-group --log-group-name {}

# Xóa S3 buckets (nếu còn)
aws s3 ls | grep p1-dev | awk '{print $3}' | \
  xargs -I {} aws s3 rb s3://{} --force

# Xóa IAM roles (nếu còn)
aws iam list-roles --query 'Roles[?contains(RoleName, `p1-dev`)].RoleName' --output text | \
  xargs -I {} aws iam delete-role --role-name {}
```

---

## 💰 Cost Estimation

### Monthly Cost Breakdown (ap-southeast-1)

| Service | Configuration | Monthly Cost (USD) |
|---------|--------------|-------------------|
| EC2 (Web) | t3.micro | ~$7.50 |
| EC2 (App) | t3.small | ~$15.00 |
| RDS MySQL | db.t3.micro | ~$15.00 |
| ALB | Standard | ~$16.00 |
| NAT Gateway | 1 AZ (if enabled) | ~$32.00 |
| CloudWatch Logs | ~5GB/month | ~$2.50 |
| CloudTrail | Standard | ~$2.00 |
| Bedrock API | ~1000 requests | ~$3.00 |
| Data Transfer | ~10GB out | ~$1.00 |
| **TOTAL (without NAT)** | | **~$62/month** |
| **TOTAL (with NAT)** | | **~$94/month** |

💡 **Cost Saving Tips:**
- Disable NAT Gateway nếu không cần internet access từ private subnet
- Dùng VPC Endpoints thay vì NAT Gateway cho AWS services
- Stop EC2 instances khi không dùng (dev environment)
- Set CloudWatch Logs retention = 7 days
- Dùng Bedrock on-demand thay vì provisioned throughput

---

## 📞 Support

Nếu gặp vấn đề, check:
1. [Troubleshooting](#troubleshooting) section
2. [SSM Access Guide](SSM_ACCESS_GUIDE.md)
3. [System Architecture](SYSTEM_ARCHITECTURE.md)

---

**Happy Deploying! 🚀**
