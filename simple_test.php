<?php
/**
 * Simple Test API - Minimal version to isolate the issue
 */

// Enable error reporting
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Set JSON header
header('Content-Type: application/json');

// Include connection
require_once 'connection.php';

echo "Starting simple test...\n";

try {
    // Get POST data
    $input = file_get_contents('php://input');
    echo "Raw input: " . $input . "\n";
    
    // If no input (CLI mode), use test data
    if (empty($input)) {
        echo "No input data, using test data...\n";
        $data = [
            'secret_key' => API_SECRET_KEY,  // Use the defined secret key
            'last_id' => 0
        ];
    } else {
        $data = json_decode($input, true);
    }
    
    echo "Decoded JSON: " . print_r($data, true) . "\n";
    
    // Check secret key
    if (!isset($data['secret_key']) || !validateAPIKey($data['secret_key'])) {
        echo json_encode(['error' => 'Invalid or missing secret key']);
        exit;
    }
    
    echo "Secret key validated\n";
    
    // Get connection
    $pdo = getDBConnection();
    if (!$pdo) {
        echo json_encode(['error' => 'Database connection failed']);
        exit;
    }
    
    echo "Database connected\n";
    
    // Simple query first
    $stmt = $pdo->query("SELECT COUNT(*) as count FROM remote_logs");
    $result = $stmt->fetch();
    echo "Total records: " . $result['count'] . "\n";
    
    // Test the problematic query
    $lastId = isset($data['last_id']) ? (int)$data['last_id'] : 0;
    echo "Last ID requested: " . $lastId . "\n";
    
    if ($lastId > 0) {
        $sql = "SELECT id, received_at, hostname, facility, message, port FROM remote_logs WHERE id > ? ORDER BY id ASC LIMIT 100";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$lastId]);
    } else {
        $sql = "SELECT id, received_at, hostname, facility, message, port FROM remote_logs ORDER BY id ASC LIMIT 100";
        $stmt = $pdo->query($sql);
    }
    
    $records = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo "Records found: " . count($records) . "\n";
    
    // Return success
    echo json_encode([
        'success' => true,
        'count' => count($records),
        'records' => $records
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    echo "Exception caught: " . $e->getMessage() . "\n";
    echo "File: " . $e->getFile() . " Line: " . $e->getLine() . "\n";
    echo json_encode([
        'error' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine()
    ]);
}
?>