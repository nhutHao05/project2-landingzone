<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

try {
    db()->query('SELECT 1');
    json_response([
        'status' => 'ok',
        'database' => 'connected',
        'app' => env_value('APP_NAME', 'OpsDesk'),
    ]);
} catch (Throwable $error) {
    error_log('Health check failed: ' . $error->getMessage());
    json_response([
        'status' => 'degraded',
        'database' => 'unavailable',
    ], 503);
}
