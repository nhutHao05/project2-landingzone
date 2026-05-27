import pool from '@/lib/db';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    await pool.query('SELECT 1');
    return NextResponse.json({
      status: 'ok',
      app: 'CyberMart',
      database: 'connected'
    });
  } catch (error) {
    return NextResponse.json({
      status: 'degraded',
      app: 'CyberMart',
      database: 'unavailable',
      error: error.message
    }, { status: 503 });
  }
}
