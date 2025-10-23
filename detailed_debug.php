<?php
/**
 * Detailed Database Diagnostic Script
 * Provides comprehensive information about PHP and database configuration
 */

// Enable error reporting for debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

echo "<h2>Detailed Database Diagnostic Script</h2>\n";
echo "<pre>\n";

echo "1. PHP Version and Configuration:\n";
echo "PHP Version: " . PHP_VERSION . "\n";
echo "PHP SAPI: " . PHP_SAPI . "\n\n";

echo "2. Available PHP Extensions:\n";
$extensions = get_loaded_extensions();
sort($extensions);
foreach ($extensions as $extension) {
    if (stripos($extension, 'pdo') !== false || stripos($extension, 'mysql') !== false) {
        echo "   $extension\n";
    }
}
echo "\n";

echo "3. PDO Drivers Available:\n";
$drivers = PDO::getAvailableDrivers();
if (empty($drivers)) {
    echo "   No PDO drivers available!\n";
    echo "   This indicates that the PDO MySQL extension is not installed or enabled.\n\n";
} else {
    foreach ($drivers as $driver) {
        echo "   $driver\n";
    }
    echo "\n";
}

// Check if we can load the PDO MySQL extension manually
echo "4. Attempting to load PDO MySQL extension:\n";
if (!extension_loaded('pdo_mysql')) {
    echo "   pdo_mysql extension is not loaded\n";
    // Try to load it
    if (function_exists('dl')) {
        if (@dl('pdo_mysql.so')) {
            echo "   Successfully loaded pdo_mysql extension\n";
        } else {
            echo "   Failed to load pdo_mysql extension\n";
        }
    } else {
        echo "   Cannot dynamically load extensions (dl function not available)\n";
    }
} else {
    echo "   pdo_mysql extension is already loaded\n";
}
echo "\n";

// Include connection file
require_once 'connection.php';

echo "5. Database Configuration:\n";
echo "DB_HOST: " . DB_HOST . "\n";
echo "DB_USER: " . DB_USER . "\n";
echo "DB_NAME: " . DB_NAME . "\n";
echo "API_SECRET_KEY: " . (defined('API_SECRET_KEY') ? substr(API_SECRET_KEY, 0, 10) . "..." : 'NOT DEFINED') . "\n\n";

echo "6. Testing database connection...\n";

try {
    $pdo = getDBConnection();
    if ($pdo) {
        echo "✓ Database connection successful!\n\n";
        
        // Test database name
        $stmt = $pdo->query("SELECT DATABASE() as db_name");
        $result = $stmt->fetch();
        echo "Connected to database: " . $result['db_name'] . "\n\n";
        
        // Check if remote_logs table exists
        echo "7. Checking if 'remote_logs' table exists...\n";
        $stmt = $pdo->query("SHOW TABLES LIKE 'remote_logs'");
        $tableExists = $stmt->fetch();
        
        if ($tableExists) {
            echo "✓ Table 'remote_logs' exists!\n\n";
            
            // Count total records
            echo "8. Counting records...\n";
            $stmt = $pdo->query("SELECT COUNT(*) as total FROM remote_logs");
            $count = $stmt->fetch();
            echo "Total records in table: " . $count['total'] . "\n\n";
        } else {
            echo "✗ Table 'remote_logs' does not exist!\n";
        }
    } else {
        echo "✗ Database connection failed!\n";
        echo "This could be due to:\n";
        echo "1. Incorrect database credentials\n";
        echo "2. Database user not having proper permissions\n";
        echo "3. PDO MySQL driver not installed or enabled\n\n";
        
        echo "Current configuration:\n";
        echo "DB_HOST: " . DB_HOST . "\n";
        echo "DB_USER: " . DB_USER . "\n";
        echo "DB_NAME: " . DB_NAME . "\n\n";
        
        echo "Troubleshooting steps:\n";
        echo "1. Verify database user exists and has permissions:\n";
        echo "   sudo mysql -u root -p -e \"SELECT User, Host FROM mysql.user WHERE User='syslog_api';\"\n\n";
        echo "2. Check if php-mysql package is installed:\n";
        echo "   sudo apt list --installed | grep php | grep mysql\n\n";
        echo "3. Check if PDO and PDO MySQL extensions are enabled:\n";
        echo "   php -m | grep -i pdo\n";
        echo "   php -m | grep -i mysql\n\n";
        echo "4. Install required packages if missing:\n";
        echo "   sudo apt install php-mysql php-pdo\n\n";
        echo "5. Explicitly enable PDO modules:\n";
        echo "   sudo phpenmod pdo pdo_mysql mysqlnd\n\n";
        echo "6. Restart Apache after installing packages:\n";
        echo "   sudo systemctl restart apache2\n\n";
        echo "7. Check Apache error logs for more details:\n";
        echo "   sudo tail -f /var/log/apache2/error.log\n\n";
    }
    
} catch (Exception $e) {
    echo "✗ Error occurred: " . $e->getMessage() . "\n";
    echo "Error details:\n";
    echo "File: " . $e->getFile() . "\n";
    echo "Line: " . $e->getLine() . "\n";
    echo "Trace:\n" . $e->getTraceAsString() . "\n";
}

echo "</pre>";

echo "<h3>Recommendations:</h3>\n";
echo "<ol>\n";
echo "<li>Ensure php-mysql package is installed: <code>sudo apt install php-mysql</code></li>\n";
echo "<li>Verify PDO MySQL extension is enabled: <code>sudo phpenmod pdo_mysql</code></li>\n";
echo "<li>Restart Apache after making changes: <code>sudo systemctl restart apache2</code></li>\n";
echo "<li>Check Apache error logs for more details: <code>sudo tail -f /var/log/apache2/error.log</code></li>\n";
echo "</ol>\n";

// Additional diagnostic information
echo "<h3>Additional Diagnostic Information:</h3>\n";
echo "<pre>\n";
echo "PHP Configuration File Path: " . php_ini_loaded_file() . "\n";
echo "PHP Extension Directory: " . ini_get('extension_dir') . "\n";
echo "Loaded Configuration File: " . (php_ini_loaded_file() ?: 'None') . "\n";
echo "</pre>\n";
?>