<?php
/**
 * Database Diagnostic Script
 * Run this to check database connectivity and table structure
 */

// Enable error reporting for debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

echo "<h2>Database Diagnostic Script</h2>\n";
echo "<pre>\n";

// Include connection file
require_once 'connection.php';

echo "1. Testing database connection...\n";

try {
    $pdo = getDBConnection();
    if ($pdo) {
        echo "✓ Database connection successful!\n\n";
        
        // Test database name
        $stmt = $pdo->query("SELECT DATABASE() as db_name");
        $result = $stmt->fetch();
        echo "Connected to database: " . $result['db_name'] . "\n\n";
        
        // Check if remote_logs table exists
        echo "2. Checking if 'remote_logs' table exists...\n";
        $stmt = $pdo->query("SHOW TABLES LIKE 'remote_logs'");
        $tableExists = $stmt->fetch();
        
        if ($tableExists) {
            echo "✓ Table 'remote_logs' exists!\n\n";
            
            // Show table structure
            echo "3. Table structure:\n";
            $stmt = $pdo->query("DESCRIBE remote_logs");
            $columns = $stmt->fetchAll();
            
            foreach ($columns as $column) {
                echo sprintf("   %-15s %-15s %s\n", 
                    $column['Field'], 
                    $column['Type'], 
                    $column['Key'] == 'PRI' ? '(PRIMARY KEY)' : ''
                );
            }
            echo "\n";
            
            // Count total records
            echo "4. Counting records...\n";
            $stmt = $pdo->query("SELECT COUNT(*) as total FROM remote_logs");
            $count = $stmt->fetch();
            echo "Total records in table: " . $count['total'] . "\n\n";
            
            if ($count['total'] > 0) {
                // Show sample records
                echo "5. Sample records (first 3):\n";
                $stmt = $pdo->query("SELECT * FROM remote_logs ORDER BY id LIMIT 3");
                $samples = $stmt->fetchAll();
                
                foreach ($samples as $record) {
                    echo "ID: " . $record['id'] . " | ";
                    echo "Received: " . ($record['received_at'] ?? 'NULL') . " | ";
                    echo "Hostname: " . ($record['hostname'] ?? 'NULL') . "\n";
                }
                echo "\n";
                
                // Test the actual query that's failing
                echo "6. Testing API query with last_id = 100...\n";
                $stmt = $pdo->prepare("SELECT id, received_at, hostname, facility, message, port 
                                     FROM remote_logs 
                                     WHERE id > :last_id 
                                     ORDER BY id ASC 
                                     LIMIT :limit");
                $lastId = 100;
                $limit = 100;
                $stmt->bindParam(':last_id', $lastId, PDO::PARAM_INT);
                $stmt->bindParam(':limit', $limit, PDO::PARAM_INT);
                $stmt->execute();
                $records = $stmt->fetchAll();
                
                echo "Query executed successfully!\n";
                echo "Records found with ID > 100: " . count($records) . "\n\n";
                
                // Test without last_id
                echo "7. Testing query without last_id filter...\n";
                $stmt = $pdo->prepare("SELECT id, received_at, hostname, facility, message, port 
                                     FROM remote_logs 
                                     ORDER BY id ASC 
                                     LIMIT :limit");
                $stmt->bindParam(':limit', $limit, PDO::PARAM_INT);
                $stmt->execute();
                $records = $stmt->fetchAll();
                
                echo "Query executed successfully!\n";
                echo "Records found: " . count($records) . "\n\n";
                
            } else {
                echo "⚠ Table is empty - no records to test with\n\n";
            }
            
        } else {
            echo "✗ Table 'remote_logs' does not exist!\n";
            echo "Available tables:\n";
            $stmt = $pdo->query("SHOW TABLES");
            $tables = $stmt->fetchAll();
            foreach ($tables as $table) {
                echo "   - " . array_values($table)[0] . "\n";
            }
            echo "\n";
        }
        
    } else {
        echo "✗ Database connection failed!\n\n";
    }
    
} catch (Exception $e) {
    echo "✗ Error occurred: " . $e->getMessage() . "\n";
    echo "Error details:\n";
    echo "File: " . $e->getFile() . "\n";
    echo "Line: " . $e->getLine() . "\n";
    echo "Trace:\n" . $e->getTraceAsString() . "\n";
}

echo "\n8. Configuration check:\n";
echo "DB_HOST: " . DB_HOST . "\n";
echo "DB_USER: " . DB_USER . "\n";
echo "DB_NAME: " . DB_NAME . "\n";
echo "API_SECRET_KEY: " . substr(API_SECRET_KEY, 0, 10) . "...\n";

echo "</pre>";
?>
