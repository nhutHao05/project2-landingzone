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

# ---------- AWS clients ----------
dynamodb = boto3.resource("dynamodb")
bedrock_runtime = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


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
            return _response(500, {"error": "Bedrock call failed"})

        logger.info("AI analysis done: severity=%s confidence=%s",
                    ai_result.get("severity"), ai_result.get("confidence"))

        # --- Save to DynamoDB ---
        incident_id = _save_to_dynamodb(ai_result, alert_payload, context_logs)
        logger.info("Incident saved: %s", incident_id)

        # --- Auto-execute safe actions (Phase 4 placeholder) ---
        auto_actions = [
            a for a in ai_result.get("remediation_actions", [])
            if a.get("auto_execute") is True and a.get("risk") == "low"
        ]
        if auto_actions:
            logger.info("Auto-execute actions (placeholder): %s",
                        [a["action"] for a in auto_actions])
            # TODO Phase 4: gọi Remediation Lambda

        return _response(200, {
            "status": "ok",
            "incident_id": incident_id,
            "severity": ai_result.get("severity"),
            "confidence": ai_result.get("confidence"),
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
        "size": 60,
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
