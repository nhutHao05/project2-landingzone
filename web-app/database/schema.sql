CREATE DATABASE IF NOT EXISTS opsdesk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE opsdesk;

CREATE TABLE IF NOT EXISTS incidents (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(180) NOT NULL,
  service_name VARCHAR(120) NOT NULL,
  severity ENUM('low', 'medium', 'high', 'critical') NOT NULL DEFAULT 'medium',
  status ENUM('open', 'investigating', 'resolved') NOT NULL DEFAULT 'open',
  owner VARCHAR(120) NOT NULL DEFAULT 'Platform Team',
  description TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_incidents_status_updated (status, updated_at),
  INDEX idx_incidents_service (service_name),
  INDEX idx_incidents_severity (severity)
) ENGINE=InnoDB;

INSERT INTO incidents (id, title, service_name, severity, status, owner, description)
VALUES
  (1, 'CloudWatch log ingestion delayed', 'observability-pipeline', 'medium', 'investigating', 'Platform Team', 'Log delivery lag detected during the last verification window.'),
  (2, 'RDS connection pool near limit', 'web-rds-layer3', 'high', 'open', 'Database Team', 'Web tier is reporting intermittent connection pressure.'),
  (3, 'ALB target health recovered', 'public-web-alb', 'low', 'resolved', 'Network Team', 'Target group returned to healthy after container restart.')
ON DUPLICATE KEY UPDATE title = title;
