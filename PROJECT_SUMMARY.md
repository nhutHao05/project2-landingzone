# 📊 PROJECT SUMMARY - AWS LANDING ZONE & SOAR SYSTEM (PROJECT 2)

## 🎯 Tổng quan

Hệ thống **Security Orchestration, Automation, and Response (SOAR)** đa tài khoản (Multi-Account) trên AWS, tích hợp Elastic SIEM, Amazon Bedrock và AWS Step Functions để tự động phát hiện, phân tích và khắc phục sự cố bảo mật.

Hạ tầng phân chia thành các môi trường riêng biệt theo cấu trúc Landing Zone:

### 1. Môi trường DevOps Account (Workloads)
*   **Layer 1 - Web Tier (CyberMart Web App)**:
    *   **Ứng dụng**: CyberMart (Next.js) - Demo storefront đơn giản.
    *   **Truy cập**: Public qua Application Load Balancer (ALB).
    *   **Port**: 8080 (internal docker/container), 80 (ALB).
*   **Layer 2 - Database Tier (RDS MySQL)**:
    *   **Database**: RDS MySQL 8.0 (database tên `opsdesk`).
    *   **Tính năng**: Lưu trữ dữ liệu sản phẩm của CyberMart, nằm hoàn toàn trong Isolated Subnet (không có kết nối internet và public access).
*   **Vulnerability Scanning**: Amazon Inspector tự động quét lỗ hổng CVE trên EC2.

### 2. Môi trường Monitor Account (Security Operations)
*   **SOAR Web Portal (Chạy trên EC2 riêng biệt)**:
    *   **Ứng dụng**: SOAR Incident Management Web Portal (Static HTML + JS + CSS) - Được nâng cấp từ ứng dụng phân tích log Streamlit (Layer 2 cũ ở DevOps) và chuyển sang chạy trên một **EC2 instance riêng biệt** trong Monitor Account (`p2-soar-web-portal`).
    *   **Nginx Web Server**: Chạy trên cổng 80 (chuyển tiếp SSM tunnel qua localhost:8080).
    *   **Auth**: AWS Cognito User Pool (OAuth2 PKCE Flow, Hosted UI) để phân quyền cho Security Analysts.
    *   **API Gateway + Lambdas**: Incidents API (GET `/incidents`), Callback API (POST `/callback`), và Retry API (POST `/retry`).
    *   **Step Functions**: State Machine thực thi quy trình khắc phục sự cố (Remediation).
    *   **Database**: DynamoDB Table (`p2-soar-incidents`) lưu trữ thông tin sự cố.

---

## 🏗️ Kiến trúc Infrastructure

```
AWS Organizations (Master Account)
├── Master Account (Management)
│     IAM Identity Center (SSO)
│     CloudTrail (org-level) ────── Ghi mọi API call ở MỌI account
│
├── DevOps Account (884264984854)
│     VPC: 10.0.0.0/16
│     🌐 CyberMart Web App (Next.js):
│       ├── ALB (public, HTTP:80)
│       ├── EC2 Web Tier (t3.micro, private subnet, port 8080)
│       └── RDS MySQL 8.0 (db.t3.micro, isolated subnet, db_name: opsdesk)
│     🔍 Amazon Inspector (EC2 Scanning)
│     Logging: CloudTrail & VPC FlowLogs → Centralized S3 (Monitor Account)
│
└── Monitor Account (247448832458)
      VPC: 10.1.0.0/16
      S3 Bucket: Centralized logs từ tất cả các account
      SQS Queues:
        ├── CloudTrail notifications
        └── Inspector findings
      EC2 Instances:
        ├── Elastic Agent (t3.small) -> Poll SQS + gửi log lên Fleet Server
        └── SOAR Web Portal (t3.small, nginx) -> Quản lý phê duyệt (Cognito SSO)
      API Gateway & DynamoDB & Lambda Functions (AI Engine, Executor, Callback, API)
      Step Functions (Remediation Workflow)
```

---

## 📦 Các Thành Phần Ứng Dụng

### 1. CyberMart Web App (Layer 1 — DevOps)
*   **Tính năng**: Hiển thị sản phẩm, thêm vào giỏ hàng, trang quản trị sản phẩm.
*   **Database**: 1 table `products` trong schema `opsdesk` trên RDS MySQL.
*   **Health Check**: Endpoint `/api/health` cho ALB.
*   **Khởi tạo DB**: Nút "Initialize DB" trong giao diện admin hoặc gọi POST `/api/init`.

### 2. SOAR Web Portal (Layer 2 — Monitor)
*   **Giao diện**: Dashboard hiển thị các số liệu thống kê sự cố (Total, Critical, Pending Approval, Resolved) và bảng chi tiết incident.
*   **Remediation Approval**:
    *   Nếu incident severity dưới High (Medium/Low), AI đề xuất và tự động chạy khắc phục.
    *   Nếu incident severity từ High trở lên (High/Critical), hệ thống sẽ chuyển sang trạng thái "Pending Approval", gửi thông báo Telegram, và chờ Analyst vào Web Portal bấm **Approve** hoặc **Reject**.
    *   Hỗ trợ nút **Retry** nếu chạy remediation bị lỗi (Trạng thái: Error).

### 3. AI Engine (Bedrock Claude Haiku 4.5)
*   **Trigger**: Nhận webhook từ Elastic SIEM.
*   **Log Context**: Query ngược lại Elasticsearch lấy 15 events liên quan (CloudTrail, VPC Flow, Web, DB, Inspector) trong vòng ±30 phút để phân tích.
*   **Bedrock Analysis**: Phân tích Timeline, Root Cause 5-Why, MITRE ATT&CK mapping và đề xuất Remediation Action dưới dạng JSON.
*   **Local Fallback**: Nếu Bedrock lỗi, Lambda sẽ kích hoạt heuristic phân tích cục bộ để tránh làm đứt gãy luồng xử lý.

### 4. Remediation Actions
*   `block_ip`: Tạo rule deny động (rule number 10-99) trên Network ACL (NACL) của VPC DevOps.
*   `isolate_ec2`: Gán instance vào Security Group "Isolation-SG" (block toàn bộ inbound/outbound).
*   `revoke_creds`: Vô hiệu hóa (Deactivate) tất cả AWS Access Keys đang hoạt động của IAM User bị ảnh hưởng.

---

## 🚀 Quy Trình Triển Khai (Deployment Process)

Việc deploy hệ thống được tự động hóa bằng script `scripts/deploy_all.sh` thông qua:
1.  **Terraform**: Deploy toàn bộ hạ tầng Landing Zone ở cả 3 account (Master, DevOps, Monitor).
2.  **Ansible**:
    *   Build Docker image cho CyberMart Web App và deploy lên EC2 Web Tier.
    *   Cấu hình Nginx, tải mã nguồn SOAR Web Portal lên EC2 Web Portal.
    *   Khởi tạo Docker, CloudWatch Agent, SSM Agent.
3.  **Database Migration**: Tự động đổ schema `database/schema.sql` vào RDS MySQL thông qua SSM Tunnel.

---

## 🚦 Trạng Thái & Tính Năng Nổi Bật

*   **Multi-Account Security Isolation**: Phân tách hạ tầng nghiêm ngặt giữa DevOps (môi trường ứng dụng) và Monitor (môi trường bảo mật/logs).
*   **Cross-Account IAM AssumeRole**: Monitor Account giả lập quyền (Assume Role) sang DevOps Account để thực hiện remediation an toàn mà không cần lưu trữ key dài hạn.
*   **Cognito User Groups**: Phân quyền truy cập Analyst Dashboard dựa theo nhóm Cognito User (Admin/Analyst/ReadOnly).
*   **Amazon Inspector Automation**: Sự cố lỗ hổng phần mềm được tự động phát hiện trên DevOps EC2, gửi message qua EventBridge cross-account target sang Monitor SQS và được AI Engine phân tích, tự động cách ly máy ảo có rủi ro cao.

---
**Last Updated**: 2026
**Version**: 2.0
**Status**: ✅ SOAR PRODUCTION READY
