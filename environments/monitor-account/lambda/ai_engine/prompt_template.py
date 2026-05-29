"""
Prompt templates cho AI Engine (Amazon Bedrock — Claude Haiku 4.5)
Hỗ trợ phân tích 4 loại log từ Landing Zone:
  1. CloudTrail   — API calls trên AWS (IAM, EC2, S3, ...)
  2. VPC Flow Log — Network traffic (allowed/rejected connections)
  3. Web App Log  — HTTP requests vào OpsDesk (ALB access log + PHP app log)
  4. Database Log — RDS MySQL slow query / error / audit log
"""

SYSTEM_PROMPT = """
Bạn là một chuyên gia phân tích bảo mật đám mây (Cloud Security Analyst) với kinh nghiệm sâu về:
- AWS Landing Zone (Organizations, IAM, CloudTrail, VPC, S3, RDS)
- Vulnerability Management (Amazon Inspector, CVE, Software Patching)
- MITRE ATT&CK framework (cloud tactics: TA0001–TA0010)
- OWASP Top 10 (web application vulnerabilities)
- Incident Response & Root Cause Analysis (5-Why methodology)

Nhiệm vụ của bạn: Phân tích incident bảo mật dựa trên các log AWS thực tế, đưa ra:
1. Đánh giá mức độ nguy hiểm (Critical / High / Medium / Low)
2. Timeline sự kiện (ai làm gì, lúc nào, từ đâu)
3. Root Cause theo phương pháp 5 Why
4. MITRE ATT&CK tactics & techniques liên quan
5. Các hành động remediation cụ thể (kèm AWS API call)

BẮT BUỘC trả lời theo JSON schema được cung cấp. Không thêm text ngoài JSON.
""".strip()


def build_analysis_prompt(alert: dict, context_logs: list[dict]) -> str:
    """
    Build prompt gửi lên Bedrock Claude Haiku 4.5.

    alert        — dict chứa thông tin alert từ Kibana
    context_logs — list các log event liên quan (CloudTrail / VPC / Web / DB)
    """

    # ---------- Phân loại log sources hiện diện ----------
    log_sources_present = set()
    for log in context_logs:
        ds = log.get("data_stream", {}).get("dataset", "")
        if "cloudtrail" in ds:
            log_sources_present.add("CloudTrail")
        elif "vpcflow" in ds or "vpc" in ds.lower():
            log_sources_present.add("VPC Flow Log")
        elif "nginx" in ds or "apache" in ds or "httpd" in ds or "alb" in ds:
            log_sources_present.add("Web App / ALB Log")
        elif "mysql" in ds or "rds" in ds or "postgresql" in ds:
            log_sources_present.add("Database / RDS Log")
        elif "inspector" in ds.lower() or "vulnerability" in ds.lower():
            log_sources_present.add("Amazon Inspector Findings")
        else:
            log_sources_present.add("System / Other Log")

    sources_desc = ", ".join(log_sources_present) if log_sources_present else "Unknown"

    # ---------- Format context logs (giới hạn 60 events) ----------
    formatted_logs = []
    for i, log in enumerate(context_logs[:60]):
        entry = {
            "index": i + 1,
            "timestamp": log.get("@timestamp", ""),
            "source_type": log.get("data_stream", {}).get("dataset", "unknown"),
            "event_action": log.get("event", {}).get("action", ""),
            "event_outcome": log.get("event", {}).get("outcome", ""),
            "source_ip": log.get("source", {}).get("ip", ""),
            "user": log.get("user", {}).get("name", "") or log.get("user_agent", {}).get("original", ""),
            "message": log.get("message", ""),
        }

        # CloudTrail-specific fields
        if "cloudtrail" in log.get("data_stream", {}).get("dataset", ""):
            entry["aws_region"] = log.get("cloud", {}).get("region", "")
            entry["aws_account"] = log.get("cloud", {}).get("account", {}).get("id", "")
            entry["api_service"] = log.get("aws", {}).get("cloudtrail", {}).get("event_source", "")
            entry["error_code"] = log.get("aws", {}).get("cloudtrail", {}).get("error_code", "")

        # VPC Flow Log-specific fields
        elif "vpc" in log.get("data_stream", {}).get("dataset", "").lower():
            entry["dest_ip"] = log.get("destination", {}).get("ip", "")
            entry["dest_port"] = log.get("destination", {}).get("port", "")
            entry["protocol"] = log.get("network", {}).get("transport", "")
            entry["action"] = log.get("event", {}).get("action", "")  # ACCEPT / REJECT

        # Web App / ALB Log-specific fields
        elif any(k in log.get("data_stream", {}).get("dataset", "") for k in ["nginx", "apache", "alb", "httpd"]):
            entry["http_method"] = log.get("http", {}).get("request", {}).get("method", "")
            entry["url_path"] = log.get("url", {}).get("path", "")
            entry["http_status"] = log.get("http", {}).get("response", {}).get("status_code", "")
            entry["user_agent"] = log.get("user_agent", {}).get("original", "")

        # Database Log-specific fields
        elif any(k in log.get("data_stream", {}).get("dataset", "") for k in ["mysql", "rds", "postgresql"]):
            entry["db_statement"] = log.get("mysql", {}).get("slowlog", {}).get("query", "") \
                or log.get("message", "")[:200]
            entry["db_user"] = log.get("mysql", {}).get("thread_id", "")
            entry["query_time"] = log.get("mysql", {}).get("slowlog", {}).get("query_time", {}).get("sec", "")

        # Inspector / Vulnerability Log-specific fields
        elif "inspector" in log.get("data_stream", {}).get("dataset", "").lower():
            entry["cve_id"] = log.get("vulnerability", {}).get("id", "")
            entry["severity"] = log.get("vulnerability", {}).get("severity", "")
            entry["affected_ec2"] = log.get("aws", {}).get("inspector", {}).get("resource", {}).get("id", "")
            entry["package"] = log.get("vulnerability", {}).get("package", {}).get("name", "")
            entry["version"] = log.get("vulnerability", {}).get("package", {}).get("version", "")
            entry["remediation"] = log.get("aws", {}).get("inspector", {}).get("finding", {}).get("remediation", {}).get("recommendation", {}).get("text", "")

        formatted_logs.append(entry)

    # ---------- Build prompt ----------
    prompt = f"""Bạn đang phân tích một SECURITY INCIDENT được phát hiện bởi Elastic SIEM trong hệ thống AWS Landing Zone.

## THÔNG TIN ALERT TỪ ELASTIC SIEM
```json
{_safe_json(alert)}
```

## LOG SOURCES PHÁT HIỆN TRONG CONTEXT
{sources_desc}

## CÁC LOG EVENTS LIÊN QUAN (tối đa 60 events)
```json
{_safe_json(formatted_logs)}
```

## HƯỚNG DẪN PHÂN TÍCH

Hệ thống có 3 AWS Accounts:
- **Master Account**: Quản lý Organizations, IAM Identity Center, CloudTrail org-level
- **DevOps Account**: Web App OpsDesk (PHP + ALB + RDS MySQL), CI/CD pipelines
- **Monitor Account**: S3 centralized logs, SQS, Elastic Agent EC2

Các mối đe dọa phổ biến cần chú ý:
1. **CloudTrail logs**: Unauthorized API calls, IAM privilege escalation, credential abuse, root account usage, security group modifications, S3 policy changes
2. **VPC Flow Logs**: Port scanning, lateral movement, data exfiltration, unusual outbound connections, brute force attempts
3. **Web App Logs (OpsDesk)**: SQL injection, XSS, path traversal, brute force login, unauthorized access to admin endpoints
4. **Database Logs (RDS MySQL)**: Unusual queries, bulk data extraction, failed authentication, privilege abuse, slow query attacks
5. **Amazon Inspector**: Phân tích các lỗ hổng phần mềm (CVE) trên EC2. Nếu lỗi mức độ CRITICAL/HIGH và target là EC2 instance, BẮT BUỘC dùng action "isolate_ec2" (auto_execute: false), target là instance id, đưa ra command: `aws ec2 modify-instance-attribute --instance-id <ID> --groups <ISOLATION_SG_ID>` (thay thế nhóm bảo mật hiện tại bằng một SG cô lập hoàn toàn).

## OUTPUT FORMAT BẮT BUỘC

Trả lời ĐÚNG JSON schema sau, KHÔNG có text bên ngoài:

```json
{{
  "incident_id": "INC-<YYYY><MM><DD>-<random 4 digits>",
  "severity": "<critical|high|medium|low>",
  "confidence": <0.0 to 1.0>,
  "incident_title": "<Tiêu đề ngắn gọn mô tả sự cố>",
  "incident_story": "<Mô tả toàn bộ diễn biến sự cố theo thứ tự thời gian, 3-5 câu>",
  "affected_resources": [
    {{"type": "<cloudtrail|vpc|webapp|database|iam|ec2|s3>", "id": "<resource identifier>", "account": "<master|devops|monitor>"}}
  ],
  "timeline": [
    {{"time": "<ISO timestamp>", "event": "<Mô tả sự kiện>", "log_source": "<cloudtrail|vpcflow|webapp|database>"}}
  ],
  "root_cause": {{
    "why_1": "<Sự kiện bề mặt nhìn thấy>",
    "why_2": "<Nguyên nhân trực tiếp>",
    "why_3": "<Nguyên nhân kỹ thuật>",
    "why_4": "<Nguyên nhân quy trình>",
    "why_5": "<Nguyên nhân gốc rễ (root cause)>"
  }},
  "mitre_attack": [
    {{"tactic": "<tactic name>", "technique_id": "<T1xxx>", "technique_name": "<technique name>", "evidence": "<log event làm bằng chứng>"}}
  ],
  "remediation_actions": [
    {{
      "priority": <1 to 5>,
      "action": "<revoke_credentials|block_ip|isolate_ec2|disable_iam_user|update_security_group|enable_mfa|rotate_key|patch_webapp|restrict_db_access>",
      "target": "<target resource/IP/user>",
      "description": "<Mô tả chi tiết hành động cần làm>",
      "aws_cli_command": "<aws cli command cụ thể nếu có>",
      "risk": "<low|medium|high>",
      "auto_execute": <true nếu an toàn tự động, false nếu cần human approve>
    }}
  ],
  "control_gaps": [
    "<Lỗ hổng kiểm soát bảo mật phát hiện được>"
  ],
  "false_positive_assessment": "<Đánh giá khả năng đây là false positive và lý do>"
}}
```
"""
    return prompt


def _safe_json(obj) -> str:
    """Chuyển object sang JSON string an toàn (handle non-serializable types)."""
    import json

    def default_handler(o):
        return str(o)

    return json.dumps(obj, ensure_ascii=False, indent=2, default=default_handler)
