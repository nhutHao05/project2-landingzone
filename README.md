# 🛡️ AWS Landing Zone & SOAR System (Project 2)

Hệ thống **Security Orchestration, Automation, and Response (SOAR)** đa tài khoản (Multi-Account) trên AWS, tích hợp Elastic SIEM và AI (Amazon Bedrock) để tự động phát hiện và khắc phục sự cố bảo mật.

---

## 📌 Các tài liệu quan trọng

Dự án này chứa nhiều tài liệu chi tiết. Vui lòng tham khảo các file sau để hiểu rõ kiến trúc và cách triển khai:

1. **[Kiến trúc tổng thể (Full Architecture)](full_architecture.md)** 
   👉 Xem chi tiết sơ đồ 3 tài khoản AWS (Master, DevOps, Monitor), luồng đi của Logs và quá trình AI tự động khắc phục (Remediation).

2. **[Hướng dẫn triển khai (Deployment Guide)](DEPLOYMENT_COMPLETE_GUIDE.md)**
   👉 Hướng dẫn từng bước (step-by-step) cách sử dụng script tự động để deploy toàn bộ hạ tầng bằng Terraform và Ansible.

3. **[Quá trình cập nhật (Walkthrough)](walkthrough.md)**
   👉 Nhật ký các tính năng đã được bổ sung và dọn dẹp trong suốt quá trình phát triển (bao gồm Phase 6).

4. **[Tổng hợp dự án (Project Summary)](PROJECT_SUMMARY.md)**
   👉 Tóm tắt kiến trúc 2-tier workload ở DevOps và trung tâm giám sát SOAR ở Monitor.

---

## 🚀 Tính năng nổi bật (Phase 1-6 Completed)

- **Multi-Account Landing Zone**: Tách biệt môi trường (Master, DevOps, Monitor) theo chuẩn AWS.
- **Centralized Logging**: Tập trung CloudTrail, VPC FlowLogs, ALB Logs từ tất cả tài khoản về một S3 Bucket duy nhất.
- **AI-Powered Remediation**: Lambda Engine tự động đánh giá mức độ nguy hiểm (Severity) bằng Amazon Bedrock (Claude Haiku 4.5) và sử dụng AWS Step Functions để thực thi khắc phục.
- **Auto-Remediation Logic**: Severity dưới High (medium, low) sẽ tự động khắc phục. High/Critical yêu cầu phê duyệt thủ công qua Web Portal.
- **Human-in-the-Loop Web Portal**: Giao diện SSO phân quyền (Cognito PKCE) cho phép chuyên viên phê duyệt (Approve/Reject) và Retry các hành động nhạy cảm.
- **Amazon Inspector Integration**: Quét lỗ hổng CVE tự động trên EC2 (DevOps Account), chuyển tiếp findings qua EventBridge → SQS → AI Engine phân tích.
- **Dynamic NACL Blocking**: Block IP tấn công trực tiếp bằng Network ACL rules trên VPC DevOps (không dùng WAF).

---
*Lưu ý: Các file `PROJECT_SUMMARY.md` cũ từ Project 1 đã được giữ lại làm tham khảo nhưng kiến trúc thực tế đã được chuyển sang SOAR Landing Zone.*
