# OpsDesk Web App

OpsDesk is a small PHP/MySQL operations dashboard for tracking incidents and service health.

It is designed for this landing zone project:

- Web tier runs the PHP container behind the ALB.
- Database tier is the RDS MySQL instance in layer 3.
- The app reads database connection settings from environment variables.

## Environment

```bash
DB_HOST=<rds-endpoint>
DB_PORT=3306
DB_USER=admin
DB_PASS=<password>
DB_NAME=opsdesk
```

## Database

Deploy the schema to the layer 3 database:

```bash
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" < database/schema.sql
```

## Local Container

```bash
docker build -t opsdesk-web .
docker run --rm -p 8080:80 --env-file .env opsdesk-web
```

Open `http://localhost:8080`.
