# CyberMart Web App

CyberMart is a lightweight Next.js/MySQL demo storefront for the landing zone web tier.

The app renders the product list on the server, ships only a tiny cart button to the browser, and exposes a health endpoint for load balancers:

```text
GET /api/health
```

The CRUD admin is available at:

```text
/admin
```

## Product API

```text
GET    /api/products
GET    /api/products/:id
POST   /api/products
PUT    /api/products/:id
DELETE /api/products/:id
```

## Environment

```bash
APP_ENV=production
APP_NAME=CyberMart

DB_HOST=<rds-endpoint>
DB_PORT=3306
DB_USER=admin
DB_PASS=<password>
DB_NAME=opsdesk
```

## Local Development

```bash
npm install
npm run dev
```

Open `http://localhost:8080`.

If the `products` table is missing, open the app and click `Initialize DB`, or run:

```bash
curl -X POST http://localhost:8080/api/init
```

## Database

To create the schema manually:

```bash
mysql -h "$DB_HOST" -P "${DB_PORT:-3306}" -u "$DB_USER" -p"$DB_PASS" < database/schema.sql
```

## Container Build

```bash
docker build -t cybermart-web .
docker run --rm -p 8080:80 --env-file .env cybermart-web
```

## Deploy

### Option A: Existing Ansible flow

From the project root:

```bash
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/deploy_web_app.yml
```

This copies `web-app`, builds the Docker image on the web EC2 host, and runs the container on host port `8080`.

### Option B: Registry flow

1. Build and push the image to your registry, for example Amazon ECR:

```bash
aws ecr get-login-password --region ap-southeast-1 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com

docker build -t cybermart-web .
docker tag cybermart-web:latest <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/cybermart-web:latest
docker push <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/cybermart-web:latest
```

2. Configure the service/container with the environment variables above.
3. Allow the web service security group to reach RDS on port `3306`.
4. Configure the load balancer target group health check path as `/api/health`.
5. Run the schema once against RDS, or visit the app and click `Initialize DB`.
