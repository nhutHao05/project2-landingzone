<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

$method = $_SERVER['REQUEST_METHOD'];

try {
    if ($method === 'GET') {
        $status = trim((string)($_GET['status'] ?? ''));
        $params = [];
        $where = '';

        if ($status !== '' && $status !== 'all') {
            $where = 'WHERE status = :status';
            $params['status'] = $status;
        }

        $summary = db()->query(
            "SELECT
                COUNT(*) AS total,
                SUM(status = 'open') AS open_count,
                SUM(status = 'investigating') AS investigating_count,
                SUM(status = 'resolved') AS resolved_count,
                SUM(severity = 'critical' AND status <> 'resolved') AS critical_open
             FROM incidents"
        )->fetch();

        $stmt = db()->prepare(
            "SELECT id, title, service_name, severity, status, owner, created_at, updated_at
             FROM incidents
             {$where}
             ORDER BY FIELD(status, 'open', 'investigating', 'resolved'), updated_at DESC
             LIMIT 50"
        );
        $stmt->execute($params);

        json_response([
            'summary' => $summary,
            'incidents' => $stmt->fetchAll(),
        ]);
    }

    if ($method === 'POST') {
        $data = request_json();
        $title = require_text($data, 'title', 180);
        $service = require_text($data, 'service_name', 120);
        $severity = strtolower(trim((string)($data['severity'] ?? 'medium')));
        $owner = trim((string)($data['owner'] ?? 'Platform Team'));
        $description = trim((string)($data['description'] ?? ''));

        if (!in_array($severity, ['low', 'medium', 'high', 'critical'], true)) {
            json_response(['error' => 'severity is invalid'], 422);
        }

        $stmt = db()->prepare(
            "INSERT INTO incidents (title, service_name, severity, status, owner, description)
             VALUES (:title, :service_name, :severity, 'open', :owner, :description)"
        );
        $stmt->execute([
            'title' => $title,
            'service_name' => $service,
            'severity' => $severity,
            'owner' => $owner !== '' ? substr($owner, 0, 120) : 'Platform Team',
            'description' => substr($description, 0, 1000),
        ]);

        json_response(['id' => (int)db()->lastInsertId()], 201);
    }

    if ($method === 'PATCH') {
        $data = request_json();
        $id = (int)($data['id'] ?? 0);
        $status = strtolower(trim((string)($data['status'] ?? '')));

        if ($id <= 0 || !in_array($status, ['open', 'investigating', 'resolved'], true)) {
            json_response(['error' => 'id or status is invalid'], 422);
        }

        $stmt = db()->prepare('UPDATE incidents SET status = :status WHERE id = :id');
        $stmt->execute(['status' => $status, 'id' => $id]);

        json_response(['updated' => $stmt->rowCount()]);
    }

    json_response(['error' => 'method not allowed'], 405);
} catch (Throwable $error) {
    error_log('Incident API failed: ' . $error->getMessage());
    json_response(['error' => 'application error'], 500);
}
