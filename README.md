# 🛡️ AWS Landing Zone & SOAR System (Project 2)

Hệ thống **Security Orchestration, Automation, and Response (SOAR)** đa tài khoản (Multi-Account) trên AWS, tích hợp Elastic SIEM và AI (Amazon Bedrock) để tự động phát hiện và khắc phục sự cố bảo mật.

---

## 📌 Các tài liệu quan trọng

Dự án này chứa nhiều tài liệu chi tiết. Vui lòng tham khảo các file sau để hiểu rõ kiến trúc và cách triển khai:

1. **[Kiến trúc tổng thể (Full Architecture)](full_architecture.md)** 
   👉 Xem chi tiết sơ đồ 3 tài khoản AWS (Master, DevOps, Monitor), luồng đi của Logs và quá trình AI tự động khắc phục (Remediation).

2. **[Hướng dẫn triển khai (Deployment Guide)](DEPLOYMENT_COMPLETE_GUIDE.md)**
   👉 Hướng dẫn từng bước (step-by-step) cách sử dụng script tự động để deploy toàn bộ hạ tầng bằng Terraform và Ansible.

3. **[Phân tích hệ thống AI (AI System Explained)](AI_SYSTEM_EXPLAINED.md)**
   👉 Đi sâu vào cách AI Engine (Bedrock Claude) phân tích Log, tìm Root Cause và map với MITRE ATT&CK.

4. **[Quá trình cập nhật (Walkthrough)](walkthrough.md)**
   👉 Nhật ký các tính năng đã được bổ sung và dọn dẹp trong suốt quá trình phát triển (bao gồm Phase 5 - Cleanup).

---

## 🚀 Tính năng nổi bật (Phase 1-5 Completed)

- **Multi-Account Landing Zone**: Tách biệt môi trường (Master, DevOps, Monitor) theo chuẩn AWS.
- **Centralized Logging**: Tập trung CloudTrail, VPC FlowLogs, Inspector từ tất cả tài khoản về một S3 Bucket duy nhất.
- **AI-Powered Remediation**: Lambda Engine tự động đánh giá mức độ nguy hiểm (Severity) và sử dụng AWS Step Functions để thực thi khắc phục.
- **Human-in-the-Loop Web Portal**: Giao diện SSO phân quyền (Cognito) cho phép chuyên viên phê duyệt (Approve/Reject) các hành động nhạy cảm.

---
*Lưu ý: Các file `PROJECT_SUMMARY.md` cũ từ Project 1 đã được giữ lại làm tham khảo nhưng kiến trúc thực tế đã được chuyển sang SOAR Landing Zone.*
