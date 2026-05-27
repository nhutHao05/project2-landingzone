CREATE DATABASE IF NOT EXISTS opsdesk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE opsdesk;

CREATE TABLE IF NOT EXISTS products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  price DECIMAL(10, 2) NOT NULL,
  image_label VARCHAR(32) NOT NULL DEFAULT 'TECH'
) ENGINE=InnoDB;

INSERT INTO products (id, name, description, price, image_label)
VALUES
  (1, 'Quantum Laptop Pro', 'Portable workstation for fast builds and cloud demos.', 1299.00, 'LAPTOP'),
  (2, 'Cyber Glasses V2', 'Lightweight AR display for maps, alerts, and quick notes.', 399.50, 'AR'),
  (3, 'Neural Mouse X', 'Low-latency ergonomic mouse for long engineering sessions.', 79.00, 'MOUSE'),
  (4, 'Holo Watch', 'Compact watch with health stats and calendar alerts.', 149.00, 'WATCH')
ON DUPLICATE KEY UPDATE name = VALUES(name);
