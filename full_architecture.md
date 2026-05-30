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
│  AWS LANDING ZONE (3 Accounts)                                                      │
│                                                                                     │
│  ┌─────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────┐ │
│  │ Master Account  │   │ DevOps Account           │   │  Monitor Account         │ │
│  │ 060026501585    │   │ 884264984854             │   │  247448832458            │ │
│  │                 │   │                          │   │                          │ │
│  │ - Organizations │   │ Web App OpsDesk          │   │ S3 Centralized Logs      │ │
│  │ - SCPs          │   │  ALB → EC2 → RDS MySQL   │   │ SQS Queue                │ │
│  │ - CloudTrail    │   │                          │   │ EC2 Elastic Agent        │ │
│  │   (org-level)   │   │ - CloudTrail logs        │   │ EC2 Web Portal (nginx)   │ │
│  │                 │   │ - VPC Flow Logs          │   │                          │ │
│  │                 │   │ - ALB Access Logs        │   │ Lambda: AI Engine        │ │
│  │                 │   │                          │   │ Lambda: Remediation      │ │
│  │                 │   │ Cross-account Role ◄─────┼───┤   (Executor + Callback)  │ │
│  │                 │   │ (assumed by Monitor)     │   │                          │ │
│  │                 │   │                          │   │ Step Functions           │ │
│  │                 │   │                          │   │ DynamoDB (Incidents)     │ │
│  │                 │   │                          │   │ API Gateway              │ │
│  │                 │   │                          │   │ Cognito User Pool        │ │
│  └────────┬────────┘   └───────────┬──────────────┘   └──────────┬───────────────┘ │
│           │ All API calls (org)    │ VPC/ALB logs                │                 │
│           └───────────────────────►│                             │                 │
│                                    └────────────────────────────►│                 │
└────────────────────────────────────────────────────────────────────────────────────┘
         All logs → S3 → SQS → Elastic Agent → Elastic SIEM (elastic.hungcx.cloud)
```

---

## Luồng SOAR hoàn chỉnh (Phase 6)

```
① Attacker tấn công hệ thống (VD: Kali scan, brute force, IAM abuse...)
         │
         ▼
② CloudTrail / VPC FlowLogs / ALB Logs ghi lại → S3 (Monitor Account)
         │
         ▼
③ SQS notification → Elastic Agent EC2 poll → gửi lên Elasticsearch
         │
         ▼
④ Kibana SIEM Rules phát hiện pattern nguy hiểm → trigger Alert
         │  (Webhook → Lambda Function URL)
         ▼
⑤ AI Engine Lambda (Monitor Account)
   ├─ Query Elasticsearch lấy 15 events context
   ├─ Gọi Amazon Bedrock (Claude Haiku) phân tích
   │    └─ fallback: local heuristic nếu Bedrock lỗi
   ├─ Lưu incident vào DynamoDB (status: Pending Approval)
   ├─ Gửi Telegram alert
   └─ Trigger Step Functions StartExecution
         │
         ▼
⑥ Step Functions State Machine (p2-soar-remediation-workflow)
   │
   ├─ ClassifySeverity
   │       ├─ auto_execute=true (Severity dưới High: medium, low) ──► ExecuteRemediation
   │       └─ auto_execute=false (Severity từ High trở lên: high, critical) ──► WaitForApproval
   │
   └─ WaitForApproval ⏳
        Lưu TaskToken vào DynamoDB
        Pause tại đây, chờ tối đa 24h (không tốn tiền)
              │
              │  Analyst vào Web Portal (http://<EC2_IP>/)
              │  Login bằng Cognito SSO (email + password)
              │  Thấy incident → click Approve hoặc Reject
              │
              ▼
        API Gateway (POST /callback, Cognito JWT required)
              │
              ▼
        Callback Lambda: lấy TaskToken từ DynamoDB
        → SendTaskSuccess (approve) hoặc SendTaskFailure (reject)
              │
              ▼
        Step Functions resume:
         ├─ Approved → ExecuteApprovedAction Lambda
         │     └─ Assume Role vào DevOps Account
         │          ├─ block_ip    → Network ACL (NACL)
         │          ├─ isolate_ec2 → Isolation Security Group
         │          └─ revoke_creds → Disable IAM Access Key
         │
         └─ Rejected → RecordRejection → DynamoDB status=Rejected
              │
              ▼
        NotifyTelegram: "✅ Resolved" hoặc "❌ Rejected"
        DynamoDB cập nhật trạng thái cuối
```

---

## Phân quyền Cross-Account (Landing Zone)

```
┌─────────────────────────────────────────────────────────────────┐
│  VẤN ĐỀ: Monitor Account cần thực thi actions ở DevOps Account │
│  (block IP, isolate EC2, revoke IAM key)                        │
└─────────────────────────────────────────────────────────────────┘

GIẢI PHÁP: IAM Cross-Account AssumeRole

Monitor Account                        DevOps Account
┌─────────────────────┐                ┌──────────────────────────────┐
│                     │                │                              │
│ Remediation Executor│                │ monitor-remediation-role     │
│ Lambda              │                │  Trust Policy:               │
│                     │  AssumeRole    │  "Principal": {              │
│ IAM Role:           │───────────────►│    "AWS": "arn:aws:iam::      │
│ remediation-executor│                │    247448832458:role/..."    │
│ -role               │                │  }                           │
│                     │◄───────────────│                              │
│                     │  Temp creds    │  Permissions:                │
│                     │  (15 min)      │  - ec2:ModifyInstanceAttribute│
│                     │                │  - iam:UpdateAccessKey       │
│                     │                │  - wafv2:UpdateIPSet         │
└─────────────────────┘                └──────────────────────────────┘

→ Cognito SSO KHÔNG liên quan đến phân quyền này.
  Cognito chỉ authenticate analyst vào Web Portal (trang HTML).
  Phân quyền 3-account được giải quyết bằng IAM AssumeRole.
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
    s3://p2-soar-centralized-logs-247448832458/AWSLogs/...
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
 ⑨ AI Engine Lambda phân tích (Bedrock Claude Haiku)
    → Lưu incident vào DynamoDB
    → Gửi Telegram alert
    → Trigger Step Functions StartExecution
                    │
                    ▼
 ⑩ Step Functions State Machine
    → WaitForApproval: lưu TaskToken vào DynamoDB, pause
    → Analyst login Web Portal (Cognito SSO)
    → Click Approve → API Gateway /callback → Callback Lambda
    → SendTaskSuccess → Step Functions resume
    → Executor Lambda assume role vào DevOps Account
    → Thực thi: block_ip / isolate_ec2 / revoke_creds
    → Update DynamoDB: Resolved
    → Telegram: "✅ Action executed"
```

---

## Phân chia trách nhiệm

```
┌──────────────────────────────────────────────────────────────────┐
│                    NHÓM MÌNH ĐÃ LÀM                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Dựng AWS Landing Zone (3 accounts + Organizations)           │
│  ✅ Cấu hình CloudTrail org-level → ghi vào S3                  │
│  ✅ Tạo S3 Bucket centralized logs (Monitor Account)             │
│  ✅ Tạo SQS Queue + S3 Event Notification                       │
│  ✅ Deploy EC2 Elastic Agent (Monitor Account)                   │
│  ✅ Web App OpsDesk (PHP) + ALB + RDS MySQL (DevOps)             │
│  ✅ CloudTrail + VPC FlowLogs + ALB Logs (DevOps Account)        │
│  ✅ AI Engine Lambda (Bedrock Claude + fallback heuristic)       │
│  ✅ Telegram Security Alerts                                     │
│  ✅ Step Functions Remediation Workflow (human-in-the-loop)      │
│  ✅ Web Portal EC2 (nginx, static HTML)                         │
│  ✅ Cognito SSO (PKCE, Hosted UI, User Pool)                    │
│  ✅ Cross-account Remediation (AssumeRole DevOps Account)        │
│  ✅ Amazon Inspector EC2 Scanning + EventBridge → SQS → AI      │
│  ✅ Retry / Error Handling (Web Portal + Step Functions)         │
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
│
│     🌐 Web App "OpsDesk" (Layer 1 — PHP App):
│       ├── ALB (public, HTTP:80) → nhận request từ internet
│       ├── EC2 Web Tier (t3.micro x2, private subnet, port 8080)
│       │     PHP App — tạo/xem/quản lý incidents (OpsDesk)
│       └── RDS MySQL 8.0 (db.t3.micro, isolated subnet)
│             Database lưu incidents, không public, không egress
│
│     🔍 Amazon Inspector (EC2 Scanning):
│       └── EventBridge Rule → Forward Critical/High findings
│             sang SQS Queue ở Monitor Account
│
│     Logging:
│       ├── CloudTrail → S3 (ghi API calls)
│       ├── VPC FlowLogs → S3 (Monitor Account)
│       └── ALB Access Logs → S3 (Monitor Account)
│
│     ⚠️  Detection KHÔNG dùng CloudWatch Alarms
│         → Tất cả rules detect đều set bên Elastic SIEM
│
└── Monitor Account
      S3 Bucket:
        └── s3://p2-soar-centralized-logs-247448832458/
              ├── AWSLogs/{org-id}/...   ← CloudTrail logs từ mọi account
              ├── vpc-flowlogs/...       ← VPC Flow Logs từ DevOps
              └── alb-logs/...           ← ALB Access Logs từ DevOps
      SQS Queues:
        ├── p2-soar-cloudtrail-notifications
        │     ← Nhận S3 event khi có file .json.gz mới
        └── p2-soar-inspector-findings
              ← Nhận Inspector findings từ DevOps EventBridge
      IAM User:
        └── p2-soar-elastic-agent
              ← Access Key để Elastic Agent đọc S3 + poll SQS
      EC2 Instances:
        ├── p2-soar-elastic-agent (t3.small)
        │     ← Chạy Elastic Agent, enroll vào Fleet anh Hưng
        │     ← Không public IP, quản lý qua SSM
        └── p2-soar-web-portal (nginx, static HTML/JS)
              ← Nâng cấp từ Layer 2 App cũ (Streamlit AI Analyzer)
              ← SOAR Dashboard + Cognito SSO + Approve/Reject/Retry
              ← Truy cập qua SSM tunnel (port 80 → localhost:8080)
      Lambda Functions:
        ├── p2-soar-ai-engine (Bedrock Claude Haiku 4.5)
        ├── p2-soar-remediation (incidents API + retry)
        ├── p2-soar-remediation-executor (block IP, isolate EC2, revoke creds)
        └── p2-soar-remediation-callback (Approve/Reject → Step Functions)
      Step Functions: p2-soar-remediation-workflow
      DynamoDB: p2-soar-incidents
      API Gateway: p2-soar-remediation-api (Cognito-protected)
      Cognito: p2-soar-portal-users (PKCE, Hosted UI)
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

### AI Engine ✅ Đã triển khai

```
Trigger: Elastic SIEM Alert → Webhook POST → Lambda Function URL
    │
    ▼
Lambda: "p2-soar-ai-engine" (Python 3.12)
    ├── Parse alert payload từ Kibana webhook
    ├── Query Elasticsearch: 15 events ±30 phút quanh alert
    │   (CloudTrail, VPC Flow, Web App, Database, Inspector logs)
    └── Build structured context (prompt_template.py)
    │
    ▼
AWS Bedrock (Claude Haiku 4.5 — anthropic.claude-haiku-4-5)
    Prompt bao gồm:
    - Thông tin alert từ Elastic SIEM
    - Log context 15 events (multi-source: CloudTrail/VPC/Web/DB/Inspector)
    - Yêu cầu phân tích: Timeline, Root Cause 5-Why, MITRE ATT&CK,
      Remediation actions (kèm AWS CLI cụ thể), Severity + Confidence
    - Output format: JSON schema bắt buộc
    │
    ▼
    ├── Lưu vào DynamoDB (p2-soar-incidents, TTL 90 ngày)
    ├── Gửi Telegram Security Alert (HTML formatted)
    └── Trigger Step Functions cho TỪNG remediation action
        ├── Severity < High (medium, low) → auto_execute = true
        └── Severity >= High (high, critical) → auto_execute = false → chờ approve

Fallback: Nếu Bedrock lỗi/throttled → Local Heuristic Engine tự phân tích
```

---

### Web Portal — Cognito SSO ✅ Đã triển khai

```
Tech stack:
  Frontend: Static HTML + Vanilla JS + CSS
  Backend: API Gateway (REST) + Lambda (Python 3.12)
  Auth: AWS Cognito User Pool (PKCE Authorization Code Flow)
  Deploy: EC2 (nginx) trên Monitor Account, truy cập qua SSM tunnel
  DB: DynamoDB (incidents)

Tính năng:
  ┌─────────────────────────────────────────────────────┐
  │  🔐 Login via Cognito Hosted UI (PKCE)              │
  │       → Redirect callback.html → exchange JWT       │
  │       → Groups: Admin / Analyst / ReadOnly          │
  └─────────────────────────────────────────────────────┘

  Dashboard:
  ├── 4 Metric Cards (Total / Critical / Pending / Resolved)
  ├── Incident List (sort by timestamp, severity badge)
  │     Mỗi incident hiển thị:
  │       - Severity badge (critical/high/medium/low)
  │       - Status badge (Pending Approval / Resolved / Rejected / Error)
  │       - Nút [Approve] [Reject] (khi Pending Approval)
  │       - Nút [Retry] (khi Error + retryable=true)
  └── Audit info: decided_by, decided_at, retry_count
```

---

### Automated Remediation ✅ Đã triển khai

```
Remediation Executor Lambda (p2-soar-remediation-executor)
Gọi bởi Step Functions, AssumeRole cross-account vào DevOps Account.

Action: "block_ip"
  → Tìm VPC DevOps (tag ManagedBy=Terraform hoặc VPC đầu tiên)
  → Lấy Network ACL (NACL) của VPC
  → Tìm rule number trống (10-99)
  → ec2.create_network_acl_entry(
        NetworkAclId='acl-xxx',
        RuleNumber=<available>,
        Protocol='-1', RuleAction='deny',
        CidrBlock='1.2.3.4/32'
    )

Action: "isolate_ec2"
  → Tìm hoặc tạo "Isolation-SG" (deny all inbound + outbound)
  → ec2.modify_instance_attribute(
        InstanceId='i-xxx',
        Groups=['sg-isolation']  ← SG chặn tất cả traffic
    )

Action: "revoke_creds"
  → iam.list_access_keys(UserName='xyz')
  → iam.update_access_key(Status='Inactive') cho mỗi key Active

Đặc biệt: reject, timeout, error
  → Cập nhật DynamoDB status tương ứng
  → Gửi Telegram thông báo

Audit trail:
  Mọi action đều được log vào DynamoDB:
  - incident_status: Resolved / Rejected / Timed Out / Error
  - decided_by: email analyst (từ Cognito JWT)
  - decided_at: ISO timestamp
  - retry_count: số lần retry (nếu có)
  - error_summary + error_detail (nếu Error)
```

---

### Amazon Inspector Integration ✅ Đã triển khai

```
DevOps Account:
  aws_inspector2_enabler (EC2 scanning)
  → Inspector quét lỗ hổng CVE tự động trên tất cả EC2 instances
  → EventBridge Rule: filter severity CRITICAL/HIGH + status ACTIVE
  → Forward findings sang SQS Queue ở Monitor Account

Monitor Account:
  SQS Queue: p2-soar-inspector-findings
  → AI Engine Lambda nhận và phân tích lỗ hổng
  → Bedrock đánh giá ảnh hưởng tới tài sản EC2
  → Đề xuất action: isolate_ec2 (cô lập máy bị nhiễm)
  → Step Functions workflow quyết định auto/manual
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
| **Phase 3** | AI Engine: Lambda + Bedrock (Claude Haiku 4.5) + Telegram Alerts + Local Fallback | ✅ Xong |
| **Phase 4** | Remediation: Step Functions + Executor Lambda (block IP via NACL, isolate EC2, revoke creds) | ✅ Xong |
| **Phase 5** | Web Portal: Cognito SSO (PKCE) + Dashboard + Approve/Reject/Retry UI | ✅ Xong |
| **Phase 6** | Inspector Integration + Retry/Error Handling + Auto-remediation dưới High + NACL dynamic blocking | ✅ Xong |

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
