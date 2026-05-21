#!/bin/bash
set -e

echo "OpsDesk database deployment"
echo "==========================="

TERRAFORM_DIR="${TERRAFORM_DIR:-../../environments/devops-account}"
SCHEMA_FILE="${SCHEMA_FILE:-../../web-app/database/schema.sql}"
DB_USER="${DB_USER:-admin}"
DB_NAME="${DB_NAME:-opsdesk}"

DB_HOST=$(cd "$TERRAFORM_DIR" && terraform output -raw db_endpoint)
DB_PASS=$(cd "$TERRAFORM_DIR" && terraform output -raw db_password)

echo "DB host: $DB_HOST"
echo "DB user: $DB_USER"
echo "DB name: $DB_NAME"

echo ""
echo "Testing database connection..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SELECT VERSION();" || {
    echo "Cannot connect to database"
    exit 1
}

echo "Connection successful"

echo ""
echo "Deploying schema from $SCHEMA_FILE"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" < "$SCHEMA_FILE"

echo ""
echo "Database deployment complete"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "
USE ${DB_NAME};
SELECT status, COUNT(*) AS incidents FROM incidents GROUP BY status ORDER BY status;
"
