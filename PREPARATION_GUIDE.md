# 📋 Hướng dẫn chuẩn bị cho ngày mai (Preparation Guide)

Tài liệu này chuẩn bị sẵn các thông tin cần thiết cho ngày mai để tiếp tục thực hiện **Phase 4 (Remediation)** và **Phase 5 (Web Portal)** một cách nhanh chóng nhất.

---

## 1. Lưu ý quan trọng về Fleet Server & Credentials

- **Fleet Server (Anh Hưng)**: 
  - URL Public: `https://elastic.hungcx.cloud:8220` (được NAT tự động trên Agent EC2 sang IP `103.98.153.3`).
  - **Không cần** nạp thêm Access Key AWS nào cho Fleet Server. Kết nối chỉ dùng duy nhất **Enrollment Token** để xác thực Agent.
- **AWS Integration (Kibana)**:
  - Cần AWS Access Key để poll SQS và đọc S3.
  - Chúng ta đang sử dụng IAM User: `project2-soar-elastic-agent` (Credentials đã được lưu an toàn trong state của Terraform).

---

## 2. Kế hoạch Phase 4: Remediation (Làm mức cơ bản)

Mục tiêu là xây dựng cơ chế xử lý cơ bản, trực quan bằng Lambda:

- **Hành động 1: Block IP**
  - Lambda sẽ cập nhật Security Group của Web App trong DevOps Account để thêm rule DENY hoặc xóa rule Ingress cũ của IP đó.
- **Hành động 2: Revoke IAM Credentials**
  - Lambda sẽ gọi API `iam:DeleteAccessKey` hoặc `iam:UpdateAccessKey` (status=Inactive) để vô hiệu hóa ngay lập tức cặp Access Key bị rò rỉ.
- **IAM Permission**:
  - Tạo 1 Role đơn giản ở DevOps Account tên là `p2-soar-remediation-role` cho phép Monitor Account assume role sang thực hiện.

---

## 3. Kế hoạch Phase 5: Web Portal (Nâng cấp Streamlit App)

Chúng ta sẽ tận dụng lại mã nguồn Streamlit từ Project 1 nằm tại:
`AI_Log_Analysis-Project-1/bedrock-log-analyzer-ui/streamlit_app.py`

**Các bước chỉnh sửa chính:**
1. **Thay đổi Data Source**: Thay vì đọc logs cục bộ hoặc CloudWatch, chúng ta sẽ sửa hàm đọc dữ liệu để query trực tiếp từ bảng DynamoDB **`p2-soar-incidents`**.
2. **Thêm UI Actions**: 
   - Với mỗi incident hiển thị, hiển thị danh sách `remediation_actions` do AI gợi ý.
   - Thêm 2 nút bấm: **`[Approve]`** và **`[Reject]`**.
3. **Trigger Action**:
   - Khi bấm `[Approve]` -> Streamlit sẽ gọi trực tiếp sang Remediation Lambda (Phase 4) để thực thi lệnh trên AWS và cập nhật trạng thái incident trong DynamoDB thành `resolved`.

---

## 4. Dựng hạ tầng DevOps Account (VPC, Web, Database)

Mã nguồn Terraform của tài khoản DevOps đã được viết sẵn tại thư mục `environments/devops-account/`.

**Các bước triển khai vào ngày mai:**
1. Mở Terminal và chuyển hướng vào thư mục DevOps:
   ```bash
   cd environments/devops-account
   ```
2. Đảm bảo Credentials của AWS CLI đang trỏ đúng vào **DevOps Account** (hoặc dùng AWS Profile tương ứng).
3. Khởi tạo và Apply hạ tầng:
   ```bash
   terraform init
   ```
   ```bash
   terraform apply -auto-approve
   ```
   *Quá trình này sẽ tự động khởi tạo VPC, ECS/EC2 Web App, và Database RDS cho ứng dụng.*

---

## 5. Các thông tin cần chuẩn bị sẵn vào ngày mai
- AWS CLI Profile có quyền quản lý cả Monitor Account và DevOps Account để deploy nhanh các IAM Role liên tài khoản.
- Tài khoản/Mật khẩu Kibana: `<KIBANA_USERNAME>` / `<KIBANA_PASSWORD>` (để test bắn alert thực tế sang Lambda).
