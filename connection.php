<?php
/**
 * Database Connection Configuration
 * Separate connection file for security and modularity
 */

// Database configuration
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'syslog_db');

// Secret key for API authentication
define('API_SECRET_KEY', 'sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d');

/**
 * Get database connection
 * @return PDO|null
 */
function getDBConnection() {
    try {
        $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false
        ];
        
        // Only add MYSQL_ATTR_INIT_COMMAND if it's defined
        if (defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
            $options[PDO::MYSQL_ATTR_INIT_COMMAND] = "SET NAMES utf8mb4";
        }
        
        $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
        
        // If the constant wasn't defined, set the charset manually
        if (!defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
            $pdo->exec("SET NAMES utf8mb4");
        }
        
        return $pdo;
    } catch (PDOException $e) {
        error_log("Database connection failed: " . $e->getMessage());
        // Also output the error to help with debugging
        error_log("PDO Error Code: " . $e->getCode());
        error_log("PDO Error Info: " . print_r($e->errorInfo, true));
        return null;
    } catch (Exception $e) {
        error_log("General error during database connection: " . $e->getMessage());
        return null;
    }
}

/**
 * Validate API secret key
 * @param string $providedKey
 * @return bool
 */
function validateAPIKey($providedKey) {
    return hash_equals(API_SECRET_KEY, $providedKey);
}
?>