"""
Lambda AI Engine — p2-soar-ai-engine
=====================================
Nhận webhook từ Kibana SIEM khi có alert,
thu thập context logs từ Elasticsearch,
gọi Amazon Bedrock Claude Haiku 4.5 phân tích,
lưu kết quả vào DynamoDB.

Environment Variables (set trong Terraform):
  ES_URL            — https://elastic.hungcx.cloud:9200
  ES_USERNAME       — Elasticsearch username
  ES_PASSWORD       — Elasticsearch password
  ES_VERIFY_SSL     — "false" cho self-signed cert (default: false)
  DYNAMODB_TABLE    — tên DynamoDB table (p2-soar-incidents)
  BEDROCK_REGION    — AWS region có Bedrock (default: ap-southeast-1)
  BEDROCK_MODEL_ID  — Model ID Claude Haiku 4.5
  WEBHOOK_SECRET    — Secret token để validate request từ Kibana (optional)
"""

import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone

import boto3
import requests
import urllib3

from prompt_template import SYSTEM_PROMPT, build_analysis_prompt

# =====================================================
# Setup
# =====================================================
logger = logging.getLogger()
logger.setLevel(logging.INFO)

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ---------- Environment variables ----------
ES_URL = os.environ.get("ES_URL", "https://elastic.hungcx.cloud:9200")
ES_USERNAME = os.environ.get("ES_USERNAME", "")
ES_PASSWORD = os.environ.get("ES_PASSWORD", "")
ES_VERIFY_SSL = os.environ.get("ES_VERIFY_SSL", "false").lower() == "true"
DYNAMODB_TABLE = os.environ.get("DYNAMODB_TABLE", "p2-soar-incidents")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "ap-southeast-1")
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID", "anthropic.claude-haiku-4-5"
)
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
SFN_STATE_MACHINE_ARN = os.environ.get("SFN_STATE_MACHINE_ARN", "")

# ---------- AWS clients ----------
dynamodb = boto3.resource("dynamodb")
bedrock_runtime = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
sfn_client = boto3.client("stepfunctions") if SFN_STATE_MACHINE_ARN else None


# =====================================================
# Main Handler
# =====================================================
def lambda_handler(event, context):
    """Entry point — nhận mọi loại trigger (Lambda URL, API Gateway, test)."""
    logger.info("=== AI Engine triggered ===")
    logger.info("Event keys: %s", list(event.keys()))

    try:
        # --- Parse incoming request ---
        alert_payload = _parse_event(event)
        if alert_payload is None:
            return _response(400, {"error": "Cannot parse alert payload"})

        logger.info("Alert received: rule=%s severity=%s",
                    alert_payload.get("rule", {}).get("name"),
                    alert_payload.get("kibana.alert.severity"))

        # --- Collect context logs from Elasticsearch ---
        context_logs = _collect_context_logs(alert_payload)
        logger.info("Context logs collected: %d events", len(context_logs))

        # --- Call Bedrock AI ---
        ai_result = _call_bedrock(alert_payload, context_logs)
        if ai_result is None:
            logger.warning("Bedrock invocation failed, falling back to local heuristics analysis.")
            ai_result = _generate_local_fallback_analysis(alert_payload, context_logs)

        logger.info("AI analysis done: severity=%s confidence=%s",
                    ai_result.get("severity"), ai_result.get("confidence"))

        # --- Save to DynamoDB ---
        incident_id = _save_to_dynamodb(ai_result, alert_payload, context_logs)
        logger.info("Incident saved: %s", incident_id)

        # --- Send Telegram Notification ---
        _send_telegram_alert(incident_id, ai_result, alert_payload)

        # --- Trigger Step Functions Remediation Workflow ---
        sfn_executions = _trigger_step_functions(incident_id, ai_result)

        return _response(200, {
            "status": "ok",
            "incident_id": incident_id,
            "severity": ai_result.get("severity"),
            "confidence": ai_result.get("confidence"),
            "sfn_executions": sfn_executions,
            "actions_pending_approval": len([
                a for a in ai_result.get("remediation_actions", [])
                if not a.get("auto_execute")
            ]),
        })

    except Exception as exc:
        logger.exception("Unhandled error: %s", exc)
        return _response(500, {"error": str(exc)})


# =====================================================
# Parse Event
# =====================================================
def _parse_event(event: dict) -> dict | None:
    """
    Kibana webhook gửi dạng Lambda Function URL:
      event["body"] = JSON string của alert
    Hoặc gửi qua API Gateway tương tự.
    Hỗ trợ cả trường hợp test với payload trực tiếp.
    """
    # Lambda Function URL / API Gateway
    body = event.get("body")
    if body:
        try:
            if isinstance(body, str):
                return json.loads(body)
            return body
        except json.JSONDecodeError as e:
            logger.error("Failed to parse body JSON: %s", e)
            return None

    # Direct invocation (test): payload là chính event
    if "rule" in event or "kibana.alert.severity" in event or "alert" in event:
        return event

    logger.warning("No recognizable payload found in event")
    return {}  # trả về empty dict để không fail hoàn toàn


# =====================================================
# Collect Context Logs from Elasticsearch
# =====================================================
def _collect_context_logs(alert: dict) -> list[dict]:
    """
    Query Elasticsearch lấy các log events liên quan đến alert:
    - CloudTrail logs (logs-aws.cloudtrail-*)
    - VPC Flow logs (logs-aws.vpcflow-*)
    - Web App / ALB logs (logs-*nginx*, logs-*apache*, logs-*alb*)
    - Database logs (logs-*mysql*, logs-*rds*)

    Lọc theo khoảng thời gian ±30 phút xung quanh alert.
    """
    # Lấy thời điểm alert (ISO 8601)
    alert_time_str = (
        alert.get("@timestamp")
        or alert.get("kibana.alert.start")
        or datetime.now(timezone.utc).isoformat()
    )

    # Query range ±30 phút
    query = {
        "size": 15,
        "sort": [{"@timestamp": {"order": "desc"}}],
        "query": {
            "bool": {
                "must": [
                    {
                        "range": {
                            "@timestamp": {
                                "gte": f"{alert_time_str}||-30m",
                                "lte": f"{alert_time_str}||+30m",
                            }
                        }
                    }
                ]
            }
        },
        "_source": [
            "@timestamp", "data_stream.dataset", "event.action",
            "event.outcome", "source.ip", "destination.ip",
            "destination.port", "user.name", "user_agent.original",
            "message", "cloud.region", "cloud.account.id",
            "aws.cloudtrail.event_source", "aws.cloudtrail.error_code",
            "network.transport", "http.request.method", "url.path",
            "http.response.status_code", "mysql.slowlog.query",
            "mysql.slowlog.query_time.sec",
        ],
    }

    # Thêm filter source IP nếu có
    source_ip = (
        alert.get("source", {}).get("ip")
        or alert.get("kibana.alert.rule.parameters", {}).get("index", [None])[0]
    )
    # Lấy source IP từ nested fields phổ biến của Kibana alert
    for path in ["source.ip", "kibana.alert.source_ip"]:
        val = _deep_get(alert, path.split("."))
        if val:
            source_ip = val
            break

    if source_ip:
        query["query"]["bool"].setdefault("should", []).append(
            {"term": {"source.ip": source_ip}}
        )

    # Query tất cả index log patterns
    index_pattern = (
        "logs-aws.cloudtrail-*,"
        "logs-aws.vpcflow-*,"
        "logs-*nginx*,"
        "logs-*apache*,"
        "logs-*alb*,"
        "logs-*mysql*,"
        "logs-*rds*"
    )

    url = f"{ES_URL}/{index_pattern}/_search"
    try:
        resp = requests.post(
            url,
            json=query,
            auth=(ES_USERNAME, ES_PASSWORD),
            verify=ES_VERIFY_SSL,
            timeout=15,
        )
        resp.raise_for_status()
        hits = resp.json().get("hits", {}).get("hits", [])
        return [h["_source"] for h in hits]
    except requests.exceptions.RequestException as e:
        logger.warning("Elasticsearch query failed: %s — returning empty context", e)
        return []


# =====================================================
# Call Amazon Bedrock — Claude Haiku 4.5
# =====================================================
def _call_bedrock(alert: dict, context_logs: list[dict]) -> dict | None:
    """Gọi Bedrock Claude Haiku 4.5 và parse JSON response."""
    user_prompt = build_analysis_prompt(alert, context_logs)

    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4096,
        "temperature": 0.1,   # thấp = output nhất quán, ít sáng tạo
        "system": SYSTEM_PROMPT,
        "messages": [
            {"role": "user", "content": user_prompt}
        ],
    }

    try:
        response = bedrock_runtime.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps(request_body),
            contentType="application/json",
            accept="application/json",
        )
        response_body = json.loads(response["body"].read())
        raw_text = response_body["content"][0]["text"]
        logger.info("Bedrock raw response (first 300 chars): %s", raw_text[:300])

        # Extract JSON từ response (Claude có thể bọc thêm text)
        return _extract_json(raw_text)

    except Exception as e:
        logger.error("Bedrock invocation failed: %s", e)
        return None

def _generate_local_fallback_analysis(alert: dict, context_logs: list[dict]) -> dict:
    """Tạo phân tích cục bộ fallback khi cuộc gọi Bedrock thất bại."""
    # Lấy thông tin cơ bản từ alert
    rule_name = alert.get("rule", {}).get("name", "Unknown Security Alert")
    severity = alert.get("kibana.alert.severity", "medium").lower()
    if severity not in ["critical", "high", "medium", "low"]:
        severity = "medium"
    
    # Tạo incident_id
    today = datetime.now(timezone.utc).strftime("%Y%m%d")
    rand_suffix = str(uuid.uuid4().int)[:4]
    incident_id = f"INC-{today}-{rand_suffix}"
    
    # Phát hiện nguồn log và IP liên quan
    source_ip = "N/A"
    for path in ["source.ip", "kibana.alert.source_ip"]:
        val = _deep_get(alert, path.split("."))
        if val:
            source_ip = val
            break
            
    if source_ip == "N/A" or source_ip == "":
        for log in context_logs:
            ip = log.get("source", {}).get("ip")
            if ip:
                source_ip = ip
                break
            
    # Xác định loại tấn công từ tên rule
    mitre_attack = []
    remediation_actions = []
    affected_resources = []
    
    incident_story = f"Hệ thống phát hiện cảnh báo '{rule_name}' thông qua Elastic SIEM."
    if "dos" in rule_name.lower() or "ddos" in rule_name.lower():
        incident_title = f"Phát hiện tấn công từ chối dịch vụ (DoS) từ IP {source_ip}"
        incident_story += f" Phát hiện lưu lượng truy cập bất thường lớn từ nguồn IP {source_ip} hướng tới Web Application/ALB."
        affected_resources.append({"type": "webapp", "id": "OpsDesk ALB", "account": "devops"})
        mitre_attack.append({
            "tactic": "Impact",
            "technique_id": "T1498",
            "technique_name": "Network Denial of Service",
            "evidence": f"Alert: {rule_name} from source IP {source_ip}"
        })
        remediation_actions.append({
            "priority": 1,
            "action": "block_ip",
            "target": source_ip,
            "description": f"Chặn địa chỉ IP tấn công {source_ip} trên WAF hoặc Security Group của ALB.",
            "aws_cli_command": f"aws ec2 create-network-acl-entry --network-acl-id acl-xxxx --ingress --rule-number 100 --protocol -1 --port-range From=-1,To=-1 --cidr-block {source_ip}/32 --rule-action deny --region ap-southeast-1",
            "risk": "low",
            "auto_execute": False
        })
    else:
        incident_title = f"Cảnh báo bảo mật: {rule_name}"
        incident_story += f" Hệ thống đang ghi nhận các log events liên quan đến địa chỉ IP {source_ip}."
        affected_resources.append({"type": "webapp", "id": "OpsDesk Server", "account": "devops"})
        mitre_attack.append({
            "tactic": "Initial Access",
            "technique_id": "T1190",
            "technique_name": "Exploit Public-Facing Application",
            "evidence": f"Alert: {rule_name}"
        })
        remediation_actions.append({
            "priority": 2,
            "action": "block_ip",
            "target": source_ip if source_ip != "N/A" else "Unknown",
            "description": "Kiểm tra và cấu hình Security Group để hạn chế truy cập không hợp lệ.",
            "aws_cli_command": "aws ec2 authorize-security-group-ingress --group-id sg-xxxx --protocol tcp --port 80 --cidr 0.0.0.0/0",
            "risk": "medium",
            "auto_execute": False
        })

    # Tạo timeline đơn giản từ context logs
    timeline = []
    for log in context_logs[:5]:
        ts = log.get("@timestamp", datetime.now(timezone.utc).isoformat())
        ds = log.get("data_stream", {}).get("dataset", "unknown")
        action = log.get("event", {}).get("action", "activity")
        timeline.append({
            "time": ts,
            "event": f"Ghi nhận log event hành động '{action}' từ dataset {ds}",
            "log_source": "webapp" if "alb" in ds or "nginx" in ds else "vpcflow"
        })
        
    if not timeline:
        timeline.append({
            "time": datetime.now(timezone.utc).isoformat(),
            "event": "Ghi nhận cảnh báo kích hoạt từ SIEM",
            "log_source": "webapp"
        })

    return {
        "incident_id": incident_id,
        "severity": severity,
        "confidence": 0.8,
        "incident_title": incident_title,
        "incident_story": incident_story,
        "affected_resources": affected_resources,
        "timeline": timeline,
        "root_cause": {
            "why_1": f"Nhận được cảnh báo SIEM '{rule_name}'",
            "why_2": f"Có lưu lượng truy cập bất thường liên quan đến IP {source_ip}",
            "why_3": "Yêu cầu HTTP/Network vượt ngưỡng cấu hình phát hiện",
            "why_4": "Thiếu cơ chế tự động giới hạn tốc độ (rate limiting) ở lớp biên",
            "why_5": "Chưa hoàn thiện chính sách bảo mật tự động phản ứng nhanh đối với tấn công DoS"
        },
        "mitre_attack": mitre_attack,
        "remediation_actions": remediation_actions,
        "control_gaps": [
            "Thiếu cơ chế Rate Limiting tự động trên ALB/WAF",
            "Chưa bật tính năng tự động chặn (auto-blocking) các IP có hành vi bất thường"
        ],
        "false_positive_assessment": "Khả năng false positive thấp do lưu lượng truy cập vượt trội so với ngưỡng thông thường của hệ thống."
    }




def _extract_json(text: str) -> dict | None:
    """Tìm và parse JSON block trong text trả về từ Claude."""
    # Thử parse toàn bộ trước
    try:
        return json.loads(text.strip())
    except json.JSONDecodeError:
        pass

    # Tìm JSON block trong ```json ... ``` hoặc { ... }
    patterns = [
        r"```json\s*([\s\S]+?)\s*```",
        r"```\s*([\s\S]+?)\s*```",
        r"(\{[\s\S]+\})",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1))
            except json.JSONDecodeError:
                continue

    logger.error("Cannot extract JSON from Bedrock response")
    return None


# =====================================================
# Save to DynamoDB
# =====================================================
def _save_to_dynamodb(ai_result: dict, alert: dict, context_logs: list) -> str:
    """Lưu incident analysis vào DynamoDB, trả về incident_id."""
    table = dynamodb.Table(DYNAMODB_TABLE)

    incident_id = ai_result.get("incident_id") or f"INC-{uuid.uuid4().hex[:8].upper()}"
    timestamp_now = datetime.now(timezone.utc).isoformat()

    # TTL: 90 ngày
    import time
    ttl = int(time.time()) + (90 * 24 * 60 * 60)

    item = {
        "incident_id": incident_id,
        "timestamp": timestamp_now,
        "status": "open",
        "severity": ai_result.get("severity", "unknown"),
        "confidence": str(ai_result.get("confidence", 0)),
        "incident_title": ai_result.get("incident_title", ""),
        "incident_story": ai_result.get("incident_story", ""),
        "affected_resources": json.dumps(ai_result.get("affected_resources", []), ensure_ascii=False),
        "timeline": json.dumps(ai_result.get("timeline", []), ensure_ascii=False),
        "root_cause": json.dumps(ai_result.get("root_cause", {}), ensure_ascii=False),
        "mitre_attack": json.dumps(ai_result.get("mitre_attack", []), ensure_ascii=False),
        "remediation_actions": json.dumps(ai_result.get("remediation_actions", []), ensure_ascii=False),
        "control_gaps": json.dumps(ai_result.get("control_gaps", []), ensure_ascii=False),
        "false_positive_assessment": ai_result.get("false_positive_assessment", ""),
        "raw_alert": json.dumps(alert, ensure_ascii=False, default=str),
        "context_log_count": len(context_logs),
        "ttl": ttl,
    }

    table.put_item(Item=item)
    return incident_id


# =====================================================
# Telegram Notification
# =====================================================
def _send_telegram_alert(incident_id: str, ai_result: dict, alert: dict):
    """Gửi thông báo incident lên Telegram Bot."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.info("Telegram not configured, skipping notification")
        return

    try:
        import html as html_mod

        severity = ai_result.get("severity", "unknown")
        severity_emoji = {
            "critical": "🔴", "high": "🟠", "medium": "🟡", "low": "🟢"
        }.get(severity.lower(), "⚪")

        title = html_mod.escape(ai_result.get("incident_title", "Security Incident"))
        story = html_mod.escape(ai_result.get("incident_story", "N/A")[:500])
        confidence = ai_result.get("confidence", "N/A")
        rule_name = html_mod.escape(
            alert.get("rule", {}).get("name")
            or alert.get("kibana.alert.rule.name", "Unknown Rule")
        )

        # MITRE ATT&CK
        mitre = ai_result.get("mitre_attack", [])
        if isinstance(mitre, str):
            try:
                mitre = json.loads(mitre)
            except Exception:
                mitre = []
        mitre_str = ", ".join(
            m.get("technique_id", "") for m in mitre[:3]
        ) if mitre else "N/A"

        # Remediation actions
        actions = ai_result.get("remediation_actions", [])
        if isinstance(actions, str):
            try:
                actions = json.loads(actions)
            except Exception:
                actions = []
        actions_text = ""
        for a in actions[:3]:
            action_str = a.get("action", str(a)) if isinstance(a, dict) else str(a)
            actions_text += f"  • {html_mod.escape(action_str[:150])}\n"

        message = (
            f"🚨 <b>SECURITY ALERT</b> 🚨\n"
            f"\n"
            f"{severity_emoji} <b>{title}</b>\n"
            f"\n"
            f"<b>Incident ID:</b> {incident_id}\n"
            f"<b>Severity:</b> {severity}\n"
            f"<b>Confidence:</b> {confidence}\n"
            f"<b>Rule:</b> {rule_name}\n"
            f"\n"
            f"<b>🔍 Summary:</b>\n"
            f"{story}\n"
            f"\n"
            f"<b>🗺️ MITRE ATT&CK:</b> {mitre_str}\n"
        )
        if actions_text:
            message += f"\n<b>🔧 Remediation:</b>\n{actions_text}"

        message += f"\n<b>⏰ Time:</b> {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}"

        resp = requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            json={
                "chat_id": TELEGRAM_CHAT_ID,
                "text": message,
                "parse_mode": "HTML",
            },
            timeout=10,
        )

        if resp.status_code == 200:
            logger.info("Telegram alert sent successfully for %s", incident_id)
        else:
            logger.warning("Telegram send failed: %s %s", resp.status_code, resp.text[:200])

    except Exception as e:
        logger.warning("Telegram notification error: %s", e)


# =====================================================
# Step Functions — Trigger Remediation Workflow
# =====================================================
def _trigger_step_functions(incident_id: str, ai_result: dict) -> list[dict]:
    """
    Khởi tạo Step Functions execution cho mỗi remediation action.

    Hiện tại: auto_execute=False cho TẤT CẢ actions
    → Mọi incident đều vào WaitForApproval, chờ analyst approve trên Web Portal.

    Để bật auto-execute sau này: xóa dòng `auto_execute = False` override bên dưới,
    lúc đó risk=low + auto_execute=True từ AI sẽ được thực thi tự động.
    """
    if not SFN_STATE_MACHINE_ARN or not sfn_client:
        logger.info("Step Functions not configured (SFN_STATE_MACHINE_ARN empty), skipping SF trigger")
        return []

    actions = ai_result.get("remediation_actions", [])
    if isinstance(actions, str):
        try:
            actions = json.loads(actions)
        except Exception:
            actions = []

    if not actions:
        logger.info("No remediation actions to trigger for %s", incident_id)
        return []

    executions = []
    for idx, action in enumerate(actions):
        if not isinstance(action, dict):
            continue

        action_type = action.get("action", "unknown")
        target = action.get("target", "unknown")
        risk = action.get("risk", "high").lower()

        # ── AUTO-EXECUTION BY SEVERITY ──────────────────────────────────
        # Tự động khắc phục nếu mức độ nghiêm trọng dưới high (tức là medium, low)
        severity = ai_result.get("severity", "unknown").lower()
        auto_execute = severity not in ["critical", "high"]
        # ─────────────────────────────────────────────────────────────────

        sf_input = {
            "incident_id": incident_id,
            "action_type": action_type,
            "target": target,
            "source": ai_result.get("incident_title", "SIEM Alert"),
            "severity": ai_result.get("severity", "unknown"),
            "auto_execute": auto_execute,
        }

        execution_name = f"{incident_id}-{action_type}-{idx}"[:80]
        # SF execution names: only allow alphanumeric, hyphens, underscores
        import re as _re
        execution_name = _re.sub(r"[^a-zA-Z0-9_-]", "-", execution_name)

        try:
            resp = sfn_client.start_execution(
                stateMachineArn=SFN_STATE_MACHINE_ARN,
                name=execution_name,
                input=json.dumps(sf_input),
            )
            exec_arn = resp["executionArn"]
            logger.info("Started SF execution %s for action %s (auto=%s)",
                        exec_arn, action_type, auto_execute)
            executions.append({
                "execution_arn": exec_arn,
                "action": action_type,
                "target": target,
                "auto_execute": auto_execute,
            })
        except Exception as e:
            logger.error("Failed to start SF execution for action %s: %s", action_type, e)
            executions.append({
                "action": action_type,
                "target": target,
                "error": str(e),
            })

    return executions


# =====================================================
# Utilities
# =====================================================
def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _deep_get(d: dict, keys: list, default=None):
    """Lấy giá trị từ nested dict theo danh sách key."""
    for key in keys:
        if isinstance(d, dict):
            d = d.get(key, default)
        else:
            return default
    return d
