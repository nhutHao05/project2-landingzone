#!/bin/bash
set -e

echo "🚀 Complete Deployment Script"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ============================================================
# Pre-flight Checks
# ============================================================
print_step "Pre-flight checks..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install it first."
    exit 1
fi

# Check Terraform
if ! command -v terraform &> /dev/null; then
    print_error "Terraform not found. Please install it first."
    exit 1
fi

# Check Ansible
if ! command -v ansible &> /dev/null; then
    print_error "Ansible not found. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi

echo "✅ All prerequisites met"
echo ""

# ============================================================
# Step 1: Bootstrap (if needed)
# ============================================================
print_step "Step 1: Bootstrap S3 Backend"
echo ""

cd ../bootstrap/

if [ ! -f "terraform.tfstate" ]; then
    echo "🔧 Initializing bootstrap..."
    terraform init
    terraform apply -auto-approve
    echo "✅ Bootstrap complete"
else
    echo "✅ Bootstrap already exists"
fi

cd ../environments/devops-account/

# ============================================================
# Step 2: Deploy Infrastructure
# ============================================================
print_step "Step 2: Deploy Infrastructure (Terraform)"
echo ""

terraform init

echo "📋 Planning infrastructure..."
terraform plan -out=tfplan

read -p "Apply infrastructure changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    terraform apply tfplan
    echo "✅ Infrastructure deployed"
else
    print_warning "Infrastructure deployment skipped"
    exit 0
fi

# Save outputs
terraform output -json > ../../scripts/terraform_outputs.json

# ============================================================
# Step 3: Fix Log Groups
# ============================================================
print_step "Step 3: Fix CloudWatch Log Groups"
echo ""

cd ../../scripts/
chmod +x fix_log_groups.sh
./fix_log_groups.sh

# ============================================================
# Step 4: Deploy Database
# ============================================================
print_step "Step 4: Deploy Database"
echo ""

chmod +x database/deploy_db.sh

read -p "Deploy database schema? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./database/deploy_db.sh
    echo "✅ Database deployed"
else
    print_warning "Database deployment skipped"
fi

# ============================================================
# Step 5: Deploy Applications (Ansible)
# ============================================================
print_step "Step 5: Deploy Applications (Ansible)"
echo ""

cd ../ansible/

# Test inventory
echo "🔍 Testing Ansible inventory..."
ansible-inventory -i inventory/aws_ec2.yml --list > /dev/null

# Test connectivity
echo "🔍 Testing instance connectivity..."
if ansible all -i inventory/aws_ec2.yml -m ping; then
    echo "✅ All instances reachable"
else
    print_error "Cannot reach instances. Check SSM connectivity."
    exit 1
fi

# Deploy
read -p "Deploy applications? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml
    echo "✅ Applications deployed"
else
    print_warning "Application deployment skipped"
fi

# ============================================================
# Step 6: Final Verification
# ============================================================
print_step "Step 6: Final Verification"
echo ""

cd ../scripts/

# Check logs
echo "📊 Checking CloudWatch logs..."
./check_logs.sh

# ============================================================
# Summary
# ============================================================
echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""

ALB_DNS=$(cd ../environments/devops-account && terraform output -raw alb_dns_name)

echo "🌐 Access URLs:"
echo "  OpsDesk: http://$ALB_DNS/"
echo "  AI Log Analyzer: Use ./access_app.sh for SSM port forwarding"
echo ""

echo "🔐 Default Accounts:"
echo ""

echo "📋 Next Steps:"
echo "  1. Test web app: curl -I http://$ALB_DNS/"
echo "  2. Access log analyzer: ./access_app.sh"
echo "  3. Check logs: ./check_logs.sh"
echo "  4. Configure Telegram bot in AI_Log_Analysis-Project-1/bedrock-log-analyzer-ui/.env"
echo ""

echo "📚 Documentation:"
echo "  See DEPLOYMENT_COMPLETE_GUIDE.md for detailed instructions"
echo ""

print_step "Happy deploying! 🚀"
