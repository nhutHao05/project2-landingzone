# 🚀 HƯỚNG DẪN DEPLOY TỰ ĐỘNG - SOAR LANDING ZONE

Tài liệu này hướng dẫn cách sử dụng kịch bản tự động (`deploy_all.sh`) để triển khai toàn bộ hạ tầng và ứng dụng lên AWS chỉ với một lệnh duy nhất.

## 📋 MỤC LỤC
1. [Tổng quan hệ thống](#1-tổng-quan-hệ-thống)
2. [Chuẩn bị môi trường](#2-chuẩn-bị-môi-trường)
3. [Chạy kịch bản tự động (deploy_all.sh)](#3-chạy-kịch-bản-tự-động)
4. [Cấu hình Elastic SIEM & AI Engine](#4-cấu-hình-elastic-siem--ai-engine)
5. [Truy cập ứng dụng](#5-truy-cập-ứng-dụng)

---

## 1. TỔNG QUAN HỆ THỐNG

Sau khi chạy xong kịch bản tự động, bạn sẽ có các thành phần sau:

### **Layer 1 - OpsDesk Web App** (Public Access)
- **Truy cập**: Qua Load Balancer (ALB).
- **Tính năng**: Ứng dụng quản lý nhân sự/vận hành (PHP) giao tiếp với RDS Database kín.

### **Layer 2 - SOAR Web Portal & AI Engine** (Monitor Account)
- **Truy cập**: Thông qua AWS SSM Port Forwarding.
- **Tính năng**: Trạm điều khiển trung tâm (Step Functions, API Gateway, Lambda) giám sát sự cố (Incidents) và ra lệnh khắc phục tự động.

### **Layer 3 - Security Workloads** (DevOps Account)
- **Tính năng**: Chứa các resource cần bảo vệ và theo dõi (Inspector, GuardDuty). Khi phát hiện Hacker, AI ở Monitor Account sẽ gọi qua (AssumeRole) để tự động cô lập máy chủ hoặc khóa IAM Account.

---

## 2. CHUẨN BỊ MÔI TRƯỜNG

Trước khi chạy script tự động, bạn cần đảm bảo các thông tin sau:

1. **Kiểm tra công cụ**: Máy ảo WSL đã cài đặt đủ `aws-cli`, `terraform`, và `ansible`.
2. **Đăng nhập AWS**: Chạy `aws configure` để lưu credentials.
3. **Cấu hình file biến Terraform**:
   Mở thư mục `environments/devops-account/` và tạo/chỉnh sửa file `terraform.tfvars`:
   ```bash
   cd environments/devops-account/
   nano terraform.tfvars
   ```
   *Dán nội dung sau (lưu ý tên project phải khớp với state cũ nếu có trên S3):*
   ```hcl
   project = "p2-soar"
   env     = "dev"
   ```

---

## 3. CHẠY KỊCH BẢN TỰ ĐỘNG

Kịch bản `deploy_all.sh` sẽ thực hiện thay bạn 5 bước lớn:
- **Step 1**: Tạo S3 Backend (nếu chưa có).
- **Step 2**: Terraform Deploy (VPC, EC2, ALB, RDS, Lambda).
- **Step 3**: Fix các lỗi liên quan tới CloudWatch Log Groups.
- **Step 4**: Kết nối xuyên hầm (SSM) vào RDS riêng tư và đổ Database Schema.
- **Step 5**: Ansible cài đặt Docker và đẩy source code OpsDesk & Web Portal lên Server.

**Thực thi lệnh:**
```bash
cd scripts/
chmod +x deploy_all.sh
./deploy_all.sh
```

**Trong quá trình chạy, script sẽ hỏi bạn vài lần (y/n):**
- *Apply infrastructure changes? (y/n)*: Bấm **y** để cho phép Terraform thay đổi hạ tầng.
- *Continue? (y/n)* (Ở phần Fix Log Groups): Bấm **y** để tiếp tục.
- *Deploy database schema? (y/n)*: Bấm **y** để tạo bảng tự động qua SSM Tunnel.
- *Deploy applications? (y/n)*: Bấm **y** để Ansible bắn code lên Server.

---

## 4. CẤU HÌNH ELASTIC SIEM & AI ENGINE (MANUAL)

Do AI Engine đã được tích hợp qua Lambda (Phase 3), bạn chỉ cần làm 1 bước cuối cùng trên Kibana để tạo "Dây thần kinh cảm giác" cho hệ thống SOAR:
1. Đăng nhập vào giao diện Kibana.
2. Vào **Security -> Rules -> Detection rules (SIEM)**.
3. Tích chọn **Tất cả các rules** đang bật.
4. Chọn **Bulk actions -> Add rule actions**.
5. Chọn Action là **Webhook**, Connector chọn cái bạn đã tạo sẵn (ví dụ: `p2-soar-ai-engine-webhook`).
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

## 5. TRUY CẬP ỨNG DỤNG

### Layer 1 - OpsDesk Web App (Public)
Mở browser: `http://<ALB-DNS-NAME>/` *(Đường link ALB này sẽ được in ra ở màn hình cuối cùng của script deploy).*
- **Admin**: `admin` / `123@`
- **Ops Staff**: `ops01` / `123@`

### Layer 2 - SOAR Web Portal (Private - Trạm điều khiển AI với Cognito SSO)
Vì Web Portal nằm trong Private Subnet (chỉ có IP nội bộ), bạn sử dụng PowerShell script để kết nối hầm SSM (SSM tunnel) chuyển tiếp cổng 80 của EC2 sang cổng 8080 local:
```powershell
cd environments/monitor-account/scripts
./start_ssm_tunnel.ps1
```
Mở trình duyệt truy cập: `http://localhost:8080/index.html`.
- **Cognito SSO Login**: Click nút **Sign in with Cognito** để đăng nhập bằng thông tin:
  - **Email**: `admin@soar.local`
  - **Password**: `Admin@123!`

---
**🎉 Chúc bạn Deploy thành công rực rỡ! 🚀**
