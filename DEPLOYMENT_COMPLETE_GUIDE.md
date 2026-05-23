# 🚀 HƯỚNG DẪN DEPLOY HOÀN CHỈNH - SOAR LANDING ZONE

## 📋 MỤC LỤC
1. [Tổng quan kiến trúc](#tổng-quan-kiến-trúc)
2. [Chuẩn bị môi trường](#chuẩn-bị-môi-trường)
3. [Deploy Infrastructure (Terraform)](#deploy-infrastructure-terraform)
4. [Deploy Database](#deploy-database)
5. [Deploy Applications (Ansible)](#deploy-applications-ansible)
6. [Cấu hình Elastic SIEM & AI Engine](#cấu-hình-elastic-siem--ai-engine)
7. [Kiểm tra Log Groups](#kiểm-tra-log-groups)
8. [Truy cập ứng dụng](#truy-cập-ứng-dụng)

---

## 🏗️ TỔNG QUAN KIẾN TRÚC

### **Layer 1 - Web Tier (Public Access via ALB)**
- **Ứng dụng**: Web QLSV (PHP)
- **Truy cập**: `http://<ALB-DNS-NAME>/qlsv`
- **Port**: 8080 (internal), 80 (ALB)
- **Log Groups**:
  - `/aws/ec2/web-tier/system` - System logs
  - `/aws/ec2/web-tier/httpd` - Apache logs
  - `/aws/ec2/web-tier/application` - PHP application logs

### **Layer 2 - App Tier (Private - SSM Access Only)**
- **Ứng dụng**: SOAR Web Portal (Nginx - Thay thế Streamlit cũ)
- **Truy cập**: SSM Port Forwarding → `http://localhost:8501`
- **Port**: 8501
- **Log Groups**:
  - `/aws/ec2/app-tier/system` - System logs
  - `/aws/ec2/app-tier/streamlit` - (Giữ nguyên log group cũ cho Web Portal)

### **Layer 3 - Security & Remediation (DevOps Account)**
- **Ứng dụng**: Remediation Lambda & API Gateway
- **Tính năng**: Thực thi các lệnh cô lập EC2, khóa IAM User, chặn IP.

---

## 🔧 CHUẨN BỊ MÔI TRƯỜNG

```bash
# Cài đặt công cụ
terraform --version  # >= 1.0
ansible --version    # >= 2.9
aws --version        # >= 2.0

# Cấu hình AWS profile
aws configure --profile default
aws sts get-caller-identity
```

---

## 🏗️ DEPLOY INFRASTRUCTURE (TERRAFORM)

Toàn bộ hạ tầng sẽ được tạo tự động bằng Terraform.

### Bước 1: Bootstrap S3 Backend
```bash
cd bootstrap/
terraform init
terraform apply -auto-approve
```

### Bước 2: Deploy Môi trường chính (VPC, EC2, ALB, RDS)
```bash
cd ../environments/dev/
terraform init
terraform apply -auto-approve

# Lưu lại các outputs quan trọng: alb_dns_name, db_endpoint, db_password
```

### Bước 3: Deploy DevOps Account (Remediation Lambda & API)
*Lưu ý: Bước này sẽ tạo ra Lambda tự động khắc phục và cấp API Gateway URL cho Frontend.*
```bash
cd ../devops-account/
terraform init
terraform apply -auto-approve

# Thành công sẽ in ra: remediation_api_url
# (Đồng thời tự động sinh file web-portal/config.json)
```

---

## 💾 DEPLOY DATABASE

```bash
cd ../../scripts/
chmod +x database/deploy_db.sh
./database/deploy_db.sh
```
*Script này sẽ đọc db_endpoint từ Terraform và tự động tạo 6 bảng, nạp 14 user mặc định.*

---

## 🚀 DEPLOY APPLICATIONS (ANSIBLE)

```bash
cd ../ansible/

# Cập nhật group_vars/all.yml với thông tin DB_HOST và DB_PASS
# Deploy toàn bộ stack (Bao gồm CloudWatch, Docker, QLSV và Web Portal)
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml
```
*Thao tác này sẽ dọn dẹp Streamlit AI cũ và đẩy source code mới của Web Portal lên EC2.*

---

## 🧠 CẤU HÌNH ELASTIC SIEM & AI ENGINE (MANUAL)

Do AI Engine đã được tích hợp qua Lambda (Phase 3), bạn chỉ cần làm 1 bước cuối cùng trên Kibana:
1. Đăng nhập vào giao diện Kibana.
2. Vào **Security -> Rules -> Detection rules (SIEM)**.
3. Tích chọn **Tất cả các rules** đang bật.
4. Chọn **Bulk actions -> Add rule actions**.
5. Chọn Action là **Webhook**, Connector chọn `p2-soar-ai-engine-webhook`.
6. Ở ô **Body**, dán đoạn JSON sau:
```json
{
  "rule_name": "{{{context.rule.name}}}",
  "rule_description": "{{{context.rule.description}}}",
  "timestamp": "{{{date}}}",
  "alerts": {{{context.alerts}}}
}
```
7. Bấm **Save**.

---

## 🌐 TRUY CẬP ỨNG DỤNG

### Layer 1 - Web QLSV (Public)
Mở browser: `http://<ALB-DNS-NAME>/qlsv`
- Admin: `admin` / `123@`
- Giảng viên: `gv01` / `123@`

### Layer 2 - SOAR Web Portal (Private - Trạm điều khiển AI)
```bash
# Lấy instance ID của app tier
APP_INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Role,Values=app" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Port forwarding qua SSM
aws ssm start-session \
    --target $APP_INSTANCE \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["8501"],"localPortNumber":["8501"]}'
```
Truy cập: `http://localhost:8501`

**Tính năng Web Portal:**
- Xem danh sách Attack Chains do AI phân tích (từ DynamoDB).
- Bấm `Approve` để tự động kích hoạt Lambda cô lập mục tiêu ngay lập tức.
- Hệ thống phòng thủ khép kín 100%.

---
**Happy Deploying! 🚀 Hệ thống SOAR đã chính thức hoàn thiện!**
