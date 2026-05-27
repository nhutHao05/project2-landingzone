import pool from '@/lib/db';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

function normalizeProduct(payload) {
  const name = String(payload.name || '').trim();
  const description = String(payload.description || '').trim();
  const price = Number(payload.price);
  const imageLabel = String(payload.image_label || 'TECH').trim().toUpperCase().slice(0, 32);

  if (!name) {
    return { error: 'Product name is required.' };
  }

  if (!Number.isFinite(price) || price < 0) {
    return { error: 'Price must be a valid positive number.' };
  }

  return {
    product: {
      name: name.slice(0, 255),
      description,
      price,
      imageLabel: imageLabel || 'TECH'
    }
  };
}

export async function GET() {
  try {
    const [rows] = await pool.query('SELECT id, name, description, price, image_label FROM products ORDER BY id');
    return NextResponse.json({ products: rows });
  } catch (error) {
    console.error('Fetch Error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}

export async function POST(request) {
  try {
    const payload = await request.json();
    const { product, error } = normalizeProduct(payload);

    if (error) {
      return NextResponse.json({ error }, { status: 422 });
    }

    const [result] = await pool.query(
      'INSERT INTO products (name, description, price, image_label) VALUES (?, ?, ?, ?)',
      [product.name, product.description, product.price, product.imageLabel]
    );

    const [rows] = await pool.query(
      'SELECT id, name, description, price, image_label FROM products WHERE id = ?',
      [result.insertId]
    );

    return NextResponse.json({ product: rows[0] }, { status: 201 });
  } catch (error) {
    console.error('Create Error:', error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }
}
