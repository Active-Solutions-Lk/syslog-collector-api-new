<?php
/**
 * Syslog Collector API - Index Page
 */

header('Content-Type: application/json');

echo json_encode([
    'success' => true,
    'message' => 'Syslog Collector API is running',
    'endpoints' => [
        'POST /api.php' => 'Main API endpoint for retrieving logs',
        'GET /debug.php' => 'Database diagnostic script',
        'GET /simple_test.php' => 'Simple test script'
    ],
    'required_fields' => [
        'secret_key' => 'API authentication key'
    ]
], JSON_PRETTY_PRINT);
?>

