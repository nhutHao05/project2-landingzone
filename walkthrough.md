# Walkthrough: Khắc phục lỗi và cấu hình thành công Elastic Agent Ingestion

Tài liệu này tổng hợp nguyên nhân sự cố, các bước xử lý và kết quả kiểm tra hoạt động của hệ thống thu thập log CloudTrail từ AWS Landing Zone.

---

## 1. Nguyên nhân sự cố ban đầu
- **Lỗi kết nối Fleet Server (Cổng `8220`)**: Fleet Server đẩy cấu hình về Agent sử dụng địa chỉ IP nội bộ `https://172.25.1.29:8220`, khiến Agent không thể kết nối từ mạng EC2.
- **Lỗi kết nối Elasticsearch (Cổng `9200`)**: Cấu phần `aws-s3-default` (Filebeat) sau khi nhận cấu hình vẫn cố gắng đẩy log lên Elasticsearch tại địa chỉ IP nội bộ `https://172.25.1.29:9200` dẫn đến lỗi timeout liên tục.

---

## 2. Giải pháp thực hiện

### A. Thiết lập Quy tắc NAT Động (iptables & systemd)
Chúng tôi đã áp dụng cơ chế bẻ hướng traffic NAT trực tiếp trên máy chủ EC2:
- Chuyển hướng các gói tin gửi tới `172.25.1.29:8220` sang IP Public của Fleet Server (`103.98.153.3:8220`).
- Chuyển hướng các gói tin gửi tới `172.25.1.29:9200` sang IP Public của Elasticsearch (`103.98.153.3:9200`).

Để đảm bảo tính bền vững (persistence):
1. **Systemd Service**: Tạo service `elastic-agent-nat.service` tự động chạy khi khởi động máy. Service này tự động phân giải tên miền `elastic.hungcx.cloud` ra IP động mới nhất rồi mới cấu hình rules `iptables`.
2. **Terraform Template**: Tích hợp quy trình cấu hình NAT này trực tiếp vào file [install-elastic-agent.sh.tpl](file:///d:/Project-2-Landing-Zone/environments/monitor-account/scripts/install-elastic-agent.sh.tpl) để tự động hóa hoàn toàn nếu EC2 được recreate sau này.

---

## 3. Xác minh hoạt động hệ thống

### A. Trạng thái Elastic Agent trên Fleet Console
- Trạng thái tổng thể: **`Healthy` (Màu xanh lá cây)**.
- Cấu phần `p2-aws-cloudtrail-integration` hoạt động bình thường, không còn cảnh báo đỏ.

![Fleet Agent Status](C:/Users/Home/.gemini/antigravity/brain/ba10fb0b-9128-4c18-96dc-5f3d23386019/fleet_status.png)

### B. Chỉ số log được nạp vào Elasticsearch
Truy vấn trực tiếp qua API Elasticsearch cho thấy Index CloudTrail đã được tạo và lưu trữ thành công tài liệu log:
- **Tên Index**: `.ds-logs-aws.cloudtrail-default-2026.05.22-000001`
- **Số lượng log ghi nhận**: `1467` bản ghi (documents).

---

## 4. Các cấu hình SIEM đã thực hiện trên Kibana

### A. Giao diện Discover & Data View
- Đã tạo thành công **Data View** mang tên **`AWS CloudTrail Logs`** (pattern: `logs-aws.cloudtrail-*`, timestamp: `@timestamp`).
- Logs CloudTrail được giải nén từ SQS/S3 hiển thị thời gian thực trên thanh thời gian (Timeline) với đầy đủ các trường thông tin (Event Outcome, Action, Source IP,...).

### B. AWS CloudTrail Dashboard
Dashboard **`[Logs AWS] CloudTrail Overview`** đã tải dữ liệu thành công và trực quan hóa toàn bộ Landing Zone:
- **Bản đồ địa lý (Source Location)**: Đánh dấu các vị trí có IP phát sinh lệnh gọi API (như Đông Nam Á).
- **Trạng thái cuộc gọi (Event Outcome)**: Biểu đồ thống kê số cuộc gọi Success (thành công) và Failure (thất bại).
- **Hành động (Actions)**: Thống kê các API như `GetBucketAcl`, `UpdateInstanceInformation`, `ListInstances`,...

![CloudTrail Dashboard Overview](C:/Users/Home/.gemini/antigravity/brain/ba10fb0b-9128-4c18-96dc-5f3d23386019/cloudtrail_dashboard.png)

### C. Kích hoạt 5 luật an ninh (Detection Rules) của Elastic SIEM
Đã nạp gói Elastic prebuilt rules và kích hoạt thành công 5 luật sau để tự động phát hiện và cảnh báo các hoạt động bất thường:
1. **AWS IAM Group Creation**: Cảnh báo khi có nhóm IAM mới được tạo (phát hiện leo thang đặc quyền).
2. **AWS SNS Topic Message Publish by Rare User**: Cảnh báo khi người dùng ít hoạt động cố gửi tin nhắn SNS.
3. **Insecure AWS EC2 VPC Security Group Ingress Rule Added**: Cảnh báo khi có rule mở cổng nguy hiểm (ví dụ: 0.0.0.0/0) trong Security Group.
4. **AWS CloudTrail Log Suspended**: Cảnh báo khi CloudTrail bị dừng hoặc cấu hình ghi log bị vô hiệu hóa (phát hiện hành vi xóa vết).
5. **AWS S3 Bucket Configuration Deletion**: Cảnh báo khi có cấu hình quan trọng của S3 bucket bị xóa.

![SIEM Detection Rules Enabled](C:/Users/Home/.gemini/antigravity/brain/ba10fb0b-9128-4c18-96dc-5f3d23386019/detection_rules.png)

---

## 5. Triển khai AI Engine & Kết nối Webhook (Phase 3)

Chúng tôi đã hoàn thành xây dựng và kích hoạt bộ máy phân tích an ninh tự động sử dụng AI:

### A. Triển khai Serverless AI Engine
- **AWS Lambda (`p2-soar-ai-engine`)**: Viết bằng Python 3.12, chịu trách nhiệm nhận dữ liệu alert từ Kibana, tự động query ngược lại Elasticsearch lấy 60 log events xung quanh sự cố (bao gồm log CloudTrail, VPC Flow, Web App, Database), sau đó gửi prompt tới **Amazon Bedrock (Claude Haiku 4.5)** để phân tích.
- **Hệ thống Prompt chuyên sâu**: Cấu hình prompt chi tiết tại `prompt_template.py` giúp AI nhận diện và xử lý 4 nguồn log của Landing Zone, phân tích timeline tấn công, chỉ ra kỹ thuật tấn công theo **MITRE ATT&CK**, thực hiện phân tích nguyên nhân gốc rễ (**5 Whys**) và gợi ý các hành động khắc phục cụ thể.
- **Incident Store (DynamoDB)**: Bảng `p2-soar-incidents` được tạo thành công với cơ chế tự động xóa bản ghi (TTL) sau 90 ngày nhằm tối ưu hóa bộ nhớ và chi phí.

### B. Đấu nối Webhook tự động từ Kibana
- Tạo thành công **Kibana Webhook Connector** trỏ trực tiếp đến Public Function URL của Lambda.
- Cấu hình chuyển tiếp alert cho cả **5 security detection rules** đã kích hoạt. Bất cứ khi nào rules này khớp (ví dụ: phát hiện tài khoản Root đăng nhập không có MFA, hoặc thêm rule mở cổng nguy hiểm trong Security Group), dữ liệu sự cố sẽ được tự động đóng gói dưới dạng JSON và bắn sang cho AI phân tích ngay lập tức.

![Kibana Webhook Configuration](C:/Users/Home/.gemini/antigravity/brain/ba10fb0b-9128-4c18-96dc-5f3d23386019/webhook_setup.png)


