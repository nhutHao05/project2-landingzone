import pool from '@/lib/db';
import { NextResponse } from 'next/server';

export async function POST() {
  const connection = await pool.getConnection();

  try {
    await connection.query(`
      CREATE TABLE IF NOT EXISTS products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        price DECIMAL(10, 2) NOT NULL,
        image_label VARCHAR(32) NOT NULL DEFAULT 'TECH'
      )
    `);

    const [columns] = await connection.query("SHOW COLUMNS FROM products LIKE 'image_label'");
    if (columns.length === 0) {
      await connection.query("ALTER TABLE products ADD COLUMN image_label VARCHAR(32) NOT NULL DEFAULT 'TECH'");
    }

    const [rows] = await connection.query('SELECT COUNT(*) AS count FROM products');
    if (rows[0].count === 0) {
      const products = [
        ['Quantum Laptop Pro', 'Portable workstation for fast builds and cloud demos.', 1299.00, 'LAPTOP'],
        ['Cyber Glasses V2', 'Lightweight AR display for maps, alerts, and quick notes.', 399.50, 'AR'],
        ['Neural Mouse X', 'Low-latency ergonomic mouse for long engineering sessions.', 79.00, 'MOUSE'],
        ['Holo Watch', 'Compact watch with health stats and calendar alerts.', 149.00, 'WATCH']
      ];

      await connection.query('INSERT INTO products (name, description, price, image_label) VALUES ?', [products]);
    }

    return NextResponse.json({ success: true, message: 'Database initialized successfully.' });
  } catch (error) {
    console.error('DB Init Error:', error);
    return NextResponse.json({ success: false, error: error.message }, { status: 500 });
  } finally {
    connection.release();
  }
}
