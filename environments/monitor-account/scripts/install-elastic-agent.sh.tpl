#!/bin/bash
# ==========================================
# Elastic Agent Install Script
# Chay tu dong khi EC2 khoi dong lan dau (User Data)
# ==========================================
set -euxo pipefail

# Ket qua cai dat se duoc ghi vao /var/log/elastic-agent-install.log
exec > >(tee /var/log/elastic-agent-install.log) 2>&1

echo "=== [1/4] Update system ==="
dnf update -y

echo "=== [1.5/4] Configure Dynamic NAT redirection for Fleet and Elasticsearch ==="
# 1. Tao script bieu dien NAT voi DNS resolution dong
cat << 'EOF' | sudo tee /opt/apply-nat.sh
#!/bin/bash
# Phan giai IP cua elastic.hungcx.cloud dong
ELASTIC_IP=$(getent ahosts elastic.hungcx.cloud | head -n1 | awk '{print $1}')
if [ -z "$ELASTIC_IP" ]; then
    ELASTIC_IP="103.98.153.3"
fi

# Xoa cac rules trung lap neu co
sudo iptables -t nat -D OUTPUT -p tcp -d 172.25.1.29 --dport 8220 -j DNAT --to-destination $ELASTIC_IP:8220 2>/dev/null || true
sudo iptables -t nat -D OUTPUT -p tcp -d 172.25.1.29 --dport 9200 -j DNAT --to-destination $ELASTIC_IP:9200 2>/dev/null || true

# Nap rules moi
sudo iptables -t nat -A OUTPUT -p tcp -d 172.25.1.29 --dport 8220 -j DNAT --to-destination $ELASTIC_IP:8220
sudo iptables -t nat -A OUTPUT -p tcp -d 172.25.1.29 --dport 9200 -j DNAT --to-destination $ELASTIC_IP:9200
echo "NAT applied successfully to $ELASTIC_IP"
EOF

sudo chmod +x /opt/apply-nat.sh

# 2. Tao file service systemd
cat << 'EOF' | sudo tee /etc/systemd/system/elastic-agent-nat.service
[Unit]
Description=Elastic Agent NAT Redirection Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/apply-nat.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now elastic-agent-nat.service

echo "=== [2/4] Download Elastic Agent ==="
# Elastic 9.3.x — khop voi version cluster cua anh Hung
cd /opt
curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-9.3.3-linux-x86_64.tar.gz
tar xzvf elastic-agent-9.3.3-linux-x86_64.tar.gz
cd elastic-agent-9.3.3-linux-x86_64

echo "=== [3/4] Install & Enroll Agent vao Fleet Server ==="
./elastic-agent install \
  --url="${fleet_url}" \
  --enrollment-token="${enrollment_token}" \
  --non-interactive \
  --insecure

echo "=== [4/4] Verify Agent dang chay ==="
sleep 10
./elastic-agent status

echo "=== Elastic Agent cai dat thanh cong! ==="
