# 🏗️ Kiến trúc tổng thể — Project 2

## Vision

```
Multi-Account AWS  →  Đẩy Logs vào Elastic (anh Hưng)  →  AI phân tích  →  Remediation ngược lại AWS
        +
  Web Portal (SSO)
```

---

## Sơ đồ tổng thể

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  NHÓM MÌNH — AWS LANDING ZONE (3 Accounts đã dựng)                                 │
│                                                                                     │
│  ┌─────────────────┐   ┌─────────────────────┐   ┌──────────────────────┐          │
│  │ Master Account  │   │ DevOps Account      │   │  Monitor Account     │          │
│  │                 │   │                     │   │                      │          │
│  │ - Organizations │   │ 🌐 Web App OpsDesk  │   │ - S3 Bucket (logs)   │          │
│  │ - IAM Identity  │   │   ALB → EC2 (PHP)   │   │ - SQS Queue          │          │
│  │   Center (SSO)  │   │   → RDS MySQL       │   │ - IAM User cho       │          │
│  │ - CloudTrail    │   │ - CloudTrail        │   │   Elastic Agent      │          │
│  │   (org-level)   │   │ - VPC FlowLogs      │   │ - EC2 Elastic Agent  │          │
│  └────────┬────────┘   └─────────┬───────────┘   └──────────┬───────────┘          │
│           │                     │                       │                           │
│           │   Logs (API calls)  │  Logs (VPC Flow)      │                           │
│           └─────────────────────┴───────────┐           │                           │
│                                             ▼           │                           │
│                                   ┌─────────────────┐   │                           │
│                                   │  S3 Bucket      │   │                           │
│                                   │  (Monitor Acct) │   │                           │
│                                   │  Centralized    │   │                           │
│                                   │  Logs           │   │                           │
│                                   └────────┬────────┘   │                           │
│                                            │            │                           │
│                                   S3 Event Notification │                           │
│                                            ▼            │                           │
│                                   ┌─────────────────┐   │                           │
│                                   │  SQS Queue      │   │                           │
│                                   │  (thông báo có  │   │                           │
│                                   │   file log mới) │   │                           │
│                                   └────────┬────────┘   │                           │
│                                            │            │                           │
│                                     Poll SQS + Đọc S3  │                           │
│                                            ▼            │                           │
│                                   ┌─────────────────┐   │                           │
│                                   │  EC2 Instance   │◄──┘                           │
│                                   │  Elastic Agent  │                               │
│                                   │  (t3.micro)     │                               │
│                                   └────────┬────────┘                               │
│                                            │                                        │
└────────────────────────────────────────────┼────────────────────────────────────────┘
                                             │
                                   Gửi logs qua HTTPS
                                   (Fleet protocol)
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  HỆ THỐNG ANH HƯNG — ELASTIC SIEM (Dựng sẵn, nhóm mình chỉ XÀI)                  │
│                                                                                     │
│  ┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐            │
│  │  Fleet Server   │ ◄──  │  Elasticsearch   │ ◄──  │  Kibana         │            │
│  │  (nhận logs từ  │      │  (lưu trữ &      │      │  (UI dashboard  │            │
│  │   Elastic Agent)│      │   index logs)    │      │   & SIEM rules) │            │
│  │                 │ ──►  │                  │ ──►  │                 │            │
│  └─────────────────┘      └──────────────────┘      └─────────────────┘            │
│                                    │                                                │
│                           700+ SIEM Rules                                           │
│                         (Detection & Alerts)                                        │
│                                                                                     │
│  URL: elastic.hungcx.cloud                                                          │
│  Fleet: elastic.hungcx.cloud:8220                                                   │
│  Kibana: elastic.hungcx.cloud:5601                                                  │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                     │ Alert triggered (webhook)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  AI ENGINE (AWS Bedrock + Lambda — trong Monitor Account)                           │
│                                                                                     │
│   Alert → Lambda → Thu thập context từ ES → Bedrock AI (Claude)                    │
│                                    │                                                │
│                          RCA + MITRE ATT&CK                                         │
│                        + Remediation Suggestions                                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                           │                    │
               Hiển thị kết quả        Thực thi remediation
                           │                    │
                           ▼                    ▼
┌───────────────────────────┐   ┌──────────────────────────────────────────────────────┐
│  WEB PORTAL               │   │  AUTOMATED REMEDIATION                               │
│  (SSO via IAM Identity    │   │                                                      │
│   Center)                 │   │  Lambda → AWS APIs:                                  │
│                           │   │  - Revoke IAM credentials                            │
│  - Dashboard incidents    │   │  - Block IP in Security Group                        │
│  - AI analysis results    │   │  - Isolate EC2 instance                              │
│  - Approve / reject       │   │  - Disable compromised user                          │
│    remediation actions    │   │  - Enable GuardDuty finding response                 │
│  - Audit history          │   │                                                      │
└───────────────────────────┘   └──────────────────────────────────────────────────────┘
```

---

## Luồng dữ liệu chi tiết (Data Flow)

```
 ① API call xảy ra ở BẤT KỲ account nào (Master / DevOps / Monitor)
                    │
                    ▼
 ② CloudTrail (Organization-level, bật ở Master Account)
    Ghi lại MỌI API call từ TẤT CẢ 3 accounts
                    │
                    ▼
 ③ Ghi file .json.gz vào S3 Bucket (nằm ở Monitor Account)
    s3://project2-soar-centralized-logs-{monitor-account-id}/AWSLogs/...
                    │
                    ▼
 ④ S3 Event Notification tự động gửi message vào SQS Queue
    "Có file mới tại AWSLogs/xxx/CloudTrail/xxx.json.gz"
                    │
                    ▼
 ⑤ EC2 Elastic Agent (Monitor Account) poll SQS
    → Nhận message → Biết path file mới
    → Download file .json.gz từ S3
    → Parse JSON, chuyển sang ECS format
                    │
                    ▼
 ⑥ Elastic Agent gửi logs qua HTTPS đến Fleet Server (anh Hưng)
    → Fleet Server: elastic.hungcx.cloud:8220
    → Dùng Enrollment Token để xác thực
                    │
                    ▼
 ⑦ Fleet Server chuyển logs vào Elasticsearch
    → Index: logs-aws.cloudtrail-*
    → Dữ liệu sẵn sàng để query & detect
                    │
                    ▼
 ⑧ Kibana SIEM Rules (scheduled queries) chạy trên Elasticsearch
    → Match pattern nguy hiểm → Tạo Alert (Low/Medium/High/Critical)
    → Hiển thị trên Kibana Dashboard
    → Webhook → trigger AI Engine (Lambda)
                    │
                    ▼
 ⑨ AI phân tích + Remediation (tự động hoặc chờ approve)
```

---

## Phân chia trách nhiệm rõ ràng

```
┌──────────────────────────────────────────────────────────────────┐
│                    NHÓM MÌNH LÀM                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Dựng AWS Landing Zone (3 accounts + Organizations)           │
│  ✅ Cấu hình CloudTrail org-level → ghi vào S3                  │
│  ✅ Tạo S3 Bucket centralized logs (Monitor Account)             │
│  ✅ Tạo SQS Queue + S3 Event Notification                       │
│  ✅ Tạo IAM User (access key) cho Elastic Agent                 │
│  ✅ Deploy EC2 + cài Elastic Agent (enroll vào Fleet anh Hưng)  │
│  ✅ Cấu hình AWS Integration trên Kibana (CloudTrail input)     │
│  ✅ Web App OpsDesk (PHP) + ALB + RDS MySQL (DevOps Account)    │
│  ✅ CloudTrail + VPC FlowLogs (DevOps Account)                  │
│  🔜 AI Engine (Lambda + Bedrock)                                │
│  🔜 Web Portal (SSO Dashboard)                                  │
│  🔜 Automated Remediation (Lambda actions)                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│              ANH HƯNG ĐÃ DỰNG SẴN (MÌNH CHỈ XÀI)              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Elasticsearch cluster (lưu trữ + index dữ liệu)            │
│  ✅ Kibana (giao diện SIEM, dashboard, detection rules)         │
│  ✅ Fleet Server (nhận logs từ Elastic Agent)                   │
│  ✅ SIEM Rules (700+ rules phát hiện đe dọa)                   │
│                                                                  │
│  Domain: elastic.hungcx.cloud                                    │
│  Fleet:  elastic.hungcx.cloud:8220                               │
│  Kibana: elastic.hungcx.cloud:5601                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Chi tiết từng thành phần

### 3 AWS Accounts (đã dựng xong)

```
AWS Organizations (Master Account)
├── Master Account (Management)
│     IAM Identity Center (SSO) ←── Tất cả user login qua đây
│     Billing & Cost Management
│     CloudTrail (org-level) ────── Ghi mọi API call ở MỌI account
│
├── DevOps Account
│     Terraform state (S3 + DynamoDB)
│     CI/CD pipelines
│
│     🌐 Web App "OpsDesk" (Incident Management):
│       ├── ALB (public, HTTP:80) → nhận request từ internet
│       ├── Layer 1: EC2 Web Tier (t3.micro x2, private subnet, port 8080)
│       │     PHP App — tạo/xem/quản lý incidents
│       ├── Layer 2: EC2 App Tier (t3.micro x2, private subnet)
│       │     Log Analysis Logic
│       └── Layer 3: RDS MySQL 8.0 (db.t3.micro, isolated subnet)
│             Database lưu incidents, không public, không egress
│
│     Logging:
│       ├── CloudTrail → S3 (ghi API calls)
│       └── VPC FlowLogs → S3 (Monitor Account)
│
│     ⚠️  Detection KHÔNG dùng CloudWatch Alarms
│         → Tất cả rules detect đều set bên Elastic SIEM
│
└── Monitor Account
      S3 Bucket:
        └── s3://project2-soar-centralized-logs-{id}/
              ├── AWSLogs/{org-id}/...   ← CloudTrail logs từ mọi account
              └── vpc-flowlogs/...       ← VPC Flow Logs từ DevOps
      SQS Queue:
        └── project2-soar-cloudtrail-notifications
              ← Nhận S3 event khi có file .json.gz mới
      IAM User:
        └── project2-soar-elastic-agent
              ← Access Key để Elastic Agent đọc S3 + poll SQS
      EC2 Instance:
        └── project2-soar-elastic-agent (t3.micro)
              ← Chạy Elastic Agent, enroll vào Fleet anh Hưng
              ← Không public IP, quản lý qua SSM
```

---

### Elastic SIEM (hệ thống anh Hưng)

```
Nhóm mình KHÔNG dựng Elastic. Anh Hưng đã dựng sẵn cluster:
  - Elasticsearch: lưu trữ & index logs
  - Kibana: giao diện SIEM + dashboard + detection rules
  - Fleet Server: quản lý & nhận logs từ các Elastic Agent

Nhóm mình chỉ cần:
  1. Cài Elastic Agent trên EC2 (Monitor Account)
  2. Enroll Agent vào Fleet Server (elastic.hungcx.cloud:8220)
  3. Cấu hình AWS CloudTrail Integration trên Kibana:
     - SQS Queue URL
     - IAM Access Key ID + Secret
  4. Verify dữ liệu vào → index logs-aws.cloudtrail-*
  5. Enable SIEM rules trên Kibana để detect threats

Dữ liệu trong Elasticsearch:
  Index: logs-aws.cloudtrail-*      (ECS format)
  Index: logs-aws.vpcflow-*         (nếu mở rộng)

SIEM Rules (chạy scheduled queries):
  → Match → Alert tạo ra
  → Alert gắn severity: Low / Medium / High / Critical

Alert Actions:
  → Hiển thị trên Kibana
  → Webhook POST → Lambda (trigger AI)
```

---

### AI Engine (sắp làm)

```
Trigger: Elastic Alert (Critical / High) → Webhook
    │
    ▼
Lambda: "collect_context"
    ├── Query Elasticsearch: 100 events xung quanh incident
    ├── Query CloudTrail S3: lịch sử IP đó 7 ngày qua
    ├── Query GuardDuty findings: account liên quan
    └── Build structured context (tối ưu token)
    │
    ▼
AWS Bedrock (Claude model)
    Prompt:
    "Đây là incident, đây là context 7 ngày.
     Hãy phân tích:
     1. Timeline tấn công
     2. Root Cause (5 Why)
     3. MITRE ATT&CK tactics/techniques
     4. Control gaps
     5. Remediation steps (kèm AWS API actions cụ thể)
     6. Severity score + Confidence"
    │
    ▼
AI Response:
    {
      "incident_story": "...",
      "root_cause": {...},
      "mitre_attack": ["T1078", "T1136"],
      "remediation_actions": [
        {
          "action": "revoke_credentials",
          "target": "iam-user-xyz",
          "aws_api": "iam:delete-access-key",
          "risk": "low",
          "auto_execute": false   ← cần human approve
        },
        {
          "action": "block_ip",
          "target": "1.2.3.4",
          "aws_api": "ec2:authorize-security-group-ingress",
          "risk": "low",
          "auto_execute": true    ← tự động thực thi luôn
        }
      ],
      "severity": "critical",
      "confidence": 0.92
    }
    │
    ├── Lưu vào DynamoDB (incident store)
    ├── Gửi về Web Portal (hiển thị)
    └── Trigger Remediation Lambda (nếu auto_execute: true)
```

---

### Web Portal — SSO (sắp làm)

```
Tech stack:
  Frontend: React / Next.js
  Backend: FastAPI (Python) hoặc Node.js
  Auth: AWS IAM Identity Center (SSO) → SAML/OIDC
  Deploy: ECS Fargate hoặc Lambda + API Gateway
  DB: DynamoDB (incidents) + Elasticsearch (logs)

Tính năng:
  ┌─────────────────────────────────────────────────────┐
  │  🔐 Login via SSO (AWS IAM Identity Center)         │
  │       → Không cần tài khoản riêng                   │
  │       → Tự động map role (Admin / Analyst / ReadOnly)│
  └─────────────────────────────────────────────────────┘

  Dashboard:
  ├── Security Overview (incidents hôm nay / tuần)
  ├── Incident List (filter by severity, account, status)
  ├── Incident Detail:
  │     - AI Analysis (timeline, RCA, MITRE)
  │     - Raw logs liên quan (query từ Elasticsearch)
  │     - Remediation Actions (danh sách các bước)
  │         ├── [✅ Auto-executed] Block IP 1.2.3.4
  │         ├── [⏳ Pending Approval] Revoke user xyz
  │         │       [Approve] [Reject] [Modify]
  │         └── [📋 Manual] Review S3 bucket policy
  ├── Remediation History (audit trail)
  └── Settings (thresholds, auto-execute rules)
```

---

### Automated Remediation (sắp làm)

```
Remediation Lambda nhận action từ AI:

Action: "revoke_credentials"
  → iam.delete_access_key(UserName='xyz', AccessKeyId='AKIA...')
  → iam.deactivate_mfa_device(...)
  → Log action vào DynamoDB

Action: "block_ip"
  → ec2.authorize_security_group_egress(
        GroupId='sg-xxx',
        IpPermissions=[{
            'IpProtocol': '-1',
            'IpRanges': [{'CidrIp': '1.2.3.4/32'}]
        }]
    )

Action: "isolate_ec2"
  → ec2.modify_instance_attribute(
        InstanceId='i-xxx',
        Groups=['sg-isolated']  ← SG chặn tất cả traffic
    )

Action: "disable_iam_user"
  → iam.update_login_profile(UserName='xyz', PasswordResetRequired=True)
  → iam.list_access_keys → delete all

Audit trail:
  Mọi action đều được log:
  {
    "timestamp": "2024-05-17T02:00:00Z",
    "incident_id": "INC-001",
    "action": "block_ip",
    "target": "1.2.3.4",
    "executed_by": "AI_AUTO",  hoặc  "user@company.com"
    "approved_by": "admin@company.com",
    "result": "success",
    "rollback_command": "aws ec2 revoke-security-group-egress ..."
  }
```

---

## Luồng hoàn chỉnh khi có tấn công

```
 🔴 Attacker brute force vào Root account, login thành công
          │
          ▼ (1-2 phút)
 ① CloudTrail ghi event → S3 (Monitor Account)
          │
          ▼ (vài giây)
 ② S3 Event → SQS Queue notification
          │
          ▼ (vài giây)
 ③ EC2 Elastic Agent poll SQS → download file từ S3 → parse logs
          │
          ▼ (gửi qua HTTPS)
 ④ Logs đến Fleet Server (anh Hưng) → Elasticsearch index
          │
          ▼ (5 phút - SIEM rule scheduled)
 ⑤ Kibana SIEM Rule "Root Login Without MFA" MATCH
    → Alert: Critical
    → Webhook → Lambda triggered
          │
          ▼ (10-20 giây)
 ⑥ Lambda thu thập context từ Elasticsearch
    → Gửi vào Bedrock AI (Claude)
          │
          ▼ (5-15 giây)
 ⑦ AI phân tích xong:
    - Timeline: 23:10 brute force bắt đầu → 23:47 login thành công
    - Root cause: MFA không được enforce ở IAM policy
    - MITRE: T1110 (Brute Force) → T1078 (Valid Accounts)
    - Remediation:
        [AUTO] Block IP 1.2.3.4 → DONE ✅
        [APPROVAL NEEDED] Revoke Root credentials
          │
          ├── Web Portal: Alert đỏ xuất hiện, analyst thấy ngay
          ├── Telegram: "🚨 Critical: Root login brute force..."
          └── Email: security-team@company.com
          │
          ▼ (Analyst vào Web Portal)
 ⑧ Analyst xem AI report → click [Approve] revoke Root credentials
          │
          ▼ (vài giây)
 ⑨ Lambda thực thi:
    → Xóa Root password (iam.delete-login-profile)
    → Ghi audit log: "Approved by analyst@company.com at 23:52"
          │
          ▼
 Incident RESOLVED ✅
 Tổng thời gian: ~15-20 phút từ lúc tấn công → remediation xong
```

---

## Thứ tự build (Roadmap)

| Phase | Việc làm | Trạng thái |
|-------|----------|------------|
| **Phase 1** | Landing Zone: Organizations + 3 accounts + CloudTrail centralized + S3 + SQS + IAM | ✅ Xong |
| **Phase 2** | Elastic Agent: EC2 → enroll Fleet anh Hưng → cấu hình AWS Integration → verify logs vào Elasticsearch | ✅ Xong |
| **Phase 3** | AI Engine: Lambda + Bedrock. Test với real alerts từ Elastic | 🔄 Đang làm |
| **Phase 4** | Remediation: Lambda actions (block IP, revoke creds, isolate EC2) | 🔜 Sắp tới |
| **Phase 5** | Web Portal: SSO login + Dashboard + Approve/Reject UI | 🔜 Sắp tới |
| **Phase 6** | Polish: Audit logs, rollback, thresholds, testing attack scenarios | 🔜 Sắp tới |

> [!IMPORTANT]
> **Điểm khác biệt so với chỉ dùng Elastic SIEM thuần:**
> - Elastic SIEM → detect + alert → **con người tự xử lý**
> - Project của mình → detect + AI analyze + **tự động / semi-auto remediate**
>
> Đây là hướng của **SOAR (Security Orchestration, Automation and Response)** — lĩnh vực đang rất hot trong enterprise security.

> [!NOTE]
> **Về Elastic SIEM:**
> Nhóm mình KHÔNG tự dựng Elasticsearch/Kibana/Fleet Server.
> Hệ thống này do **anh Hưng** đã dựng sẵn tại `elastic.hungcx.cloud`.
> Nhóm mình chỉ cần deploy **Elastic Agent** trên EC2 (Monitor Account) và enroll vào Fleet Server của ảnh.
