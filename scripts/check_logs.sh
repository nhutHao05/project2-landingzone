#!/bin/bash
set -e

echo "📊 CloudWatch Log Groups Status Check"
echo "======================================"
echo ""

AWS_REGION="ap-southeast-1"

# Danh sách log groups theo Streamlit app
LOG_GROUPS=(
    "/aws/vpc/flowlogs"
    "/aws/cloudtrail/logs"
    "/aws/ec2/web-tier/system"
    "/aws/ec2/web-tier/httpd"
    "/aws/ec2/web-tier/application"
    "/aws/ec2/app-tier/system"
    "/aws/ec2/app-tier/streamlit"
    "/aws/rds/mysql/error"
    "/aws/rds/mysql/slowquery"
)

echo "🔍 Checking 9 log groups..."
echo ""

for log_group in "${LOG_GROUPS[@]}"; do
    echo -n "  📂 $log_group ... "
    
    # Kiểm tra log group tồn tại
    if aws logs describe-log-groups \
        --log-group-name-prefix "$log_group" \
        --region "$AWS_REGION" \
        --query "logGroups[?logGroupName=='$log_group']" \
        --output text | grep -q "$log_group"; then
        
        # Đếm số log streams
        stream_count=$(aws logs describe-log-streams \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" \
            --query 'length(logStreams)' \
            --output text 2>/dev/null || echo "0")
        
        # Lấy log event gần nhất
        latest_event=$(aws logs filter-log-events \
            --log-group-name "$log_group" \
            --region "$AWS_REGION" \
            --max-items 1 \
            --query 'events[0].timestamp' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$latest_event" != "0" ] && [[ ! "$latest_event" == *"None"* ]]; then
            # Extract only the first sequence of digits to avoid newline/None issues
            clean_event=$(echo "$latest_event" | grep -o -E '[0-9]+' | head -n 1)
            if [ -n "$clean_event" ]; then
                latest_time=$(date -d "@$((clean_event / 1000))" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
                echo "✅ ACTIVE ($stream_count streams, latest: $latest_time)"
            else
                echo "⚠️  EXISTS but NO LOGS YET ($stream_count streams)"
            fi
        else
            echo "⚠️  EXISTS but NO LOGS YET ($stream_count streams)"
        fi
    else
        echo "❌ NOT FOUND"
    fi
done

echo ""
echo "📈 Summary by Category:"
echo ""

# Infrastructure
echo "🏗️  Infrastructure Logs:"
echo "  - VPC Flow Logs: /aws/vpc/flowlogs"
echo "  - CloudTrail: /aws/cloudtrail/logs"
echo ""

# Web Tier
echo "🌐 Web Tier (Layer 1):"
echo "  - System: /aws/ec2/web-tier/system"
echo "  - HTTP Server: /aws/ec2/web-tier/httpd"
echo "  - Application: /aws/ec2/web-tier/application"
echo ""

# App Tier
echo "🤖 App Tier (Layer 2):"
echo "  - System: /aws/ec2/app-tier/system"
echo "  - Streamlit: /aws/ec2/app-tier/streamlit"
echo ""

# Database
echo "💾 Database:"
echo "  - Error Logs: /aws/rds/mysql/error"
echo "  - Slow Query: /aws/rds/mysql/slowquery"
echo ""

echo "✅ Check complete!"
