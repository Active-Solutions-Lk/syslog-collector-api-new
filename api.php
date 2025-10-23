<?php
/**
 * Remote Logs API Endpoint
 * Accepts POST requests with secret key authentication
 * Returns log records after specified LAST_ID
 */

// Include database connection
require_once 'connection.php';

// Set proper headers for API response
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'error' => 'Method not allowed. Only POST requests are accepted.',
        'code' => 'METHOD_NOT_ALLOWED'
    ]);
    exit;
}

// Function to send JSON response
function sendResponse($success, $data = null, $error = null, $code = null, $httpCode = 200) {
    http_response_code($httpCode);
    $response = ['success' => $success];
    
    if ($data !== null) {
        $response['data'] = $data;
    }
    
    if ($error !== null) {
        $response['error'] = $error;
    }
    
    if ($code !== null) {
        $response['code'] = $code;
    }
    
    echo json_encode($response, JSON_PRETTY_PRINT);
    exit;
}

try {
    // Get POST data
    $input = file_get_contents('php://input');
    $data = json_decode($input, true);
    
    // Check if JSON is valid
    if (json_last_error() !== JSON_ERROR_NONE) {
        sendResponse(false, null, 'Invalid JSON format', 'INVALID_JSON', 400);
    }
    
    // Validate required fields
    if (!isset($data['secret_key'])) {
        sendResponse(false, null, 'Secret key is required', 'MISSING_SECRET_KEY', 400);
    }
    
    // Validate secret key
    if (!validateAPIKey($data['secret_key'])) {
        sendResponse(false, null, 'Invalid secret key', 'INVALID_SECRET_KEY', 401);
    }
    
    // Get database connection
    $pdo = getDBConnection();
    if (!$pdo) {
        sendResponse(false, null, 'Database connection failed', 'DB_CONNECTION_ERROR', 500);
    }
    
    // Check if LAST_ID is provided
    $lastId = isset($data['last_id']) ? (int)$data['last_id'] : 0;
    
    // Prepare SQL query - removed limit to return all records
    if ($lastId > 0) {
        $sql = "SELECT id, received_at, hostname, facility, message, port 
                FROM remote_logs 
                WHERE id > :last_id 
                ORDER BY id ASC";
    } else {
        $sql = "SELECT id, received_at, hostname, facility, message, port 
                FROM remote_logs 
                ORDER BY id ASC";
    }
    
    $stmt = $pdo->prepare($sql);
    
    if ($lastId > 0) {
        $stmt->bindParam(':last_id', $lastId, PDO::PARAM_INT);
        $stmt->execute();
    } else {
        $stmt->execute();
    }
    
    $records = $stmt->fetchAll();
    
    // Get total count for information
    $countSql = $lastId > 0 ? 
        "SELECT COUNT(*) as total FROM remote_logs WHERE id > :last_id" : 
        "SELECT COUNT(*) as total FROM remote_logs";
    
    $countStmt = $pdo->prepare($countSql);
    if ($lastId > 0) {
        $countStmt->bindParam(':last_id', $lastId, PDO::PARAM_INT);
    }
    $countStmt->execute();
    $totalCount = $countStmt->fetch()['total'];
    
    // Prepare response data
    $responseData = [
        'records' => $records,
        'count' => count($records),
        'total_available' => (int)$totalCount,
        'last_id_requested' => $lastId
        // Removed limit from response data since it's no longer used
    ];
    
    // Add next_last_id if there are records
    if (!empty($records)) {
        $responseData['next_last_id'] = end($records)['id'];
    }
    
    sendResponse(true, $responseData);
    
} catch (PDOException $e) {
    error_log("Database error: " . $e->getMessage());
    sendResponse(false, null, 'Database query failed', 'DB_QUERY_ERROR', 500);
} catch (Exception $e) {
    error_log("General error: " . $e->getMessage());
    sendResponse(false, null, 'Internal server error', 'INTERNAL_ERROR', 500);
}
?>