#!/bin/bash

# Diagnostic and Fix Script for Database User Issues
# This script diagnoses and fixes MySQL user permission problems

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  MySQL User Diagnostic & Fix Tool     ${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Configuration
DB_NAME="syslog_db"
API_USER="syslog_api"
MYSQL_ROOT_PASSWORD=""

# Step 1: Check if connection.php exists and read current password
print_step "Step 1: Reading current configuration..."
if [ -f "/var/www/html/api/connection.php" ]; then
    CURRENT_PASSWORD=$(grep "define('DB_PASS'" /var/www/html/api/connection.php | sed -n "s/.*define('DB_PASS', '\(.*\)');.*/\1/p")
    print_status "Found existing password in connection.php: ${CURRENT_PASSWORD}"
else
    print_warning "connection.php not found, will create new password"
    CURRENT_PASSWORD=""
fi
echo

# Step 2: Check if MySQL user exists
print_step "Step 2: Checking if MySQL user exists..."
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    USER_EXISTS=$(mysql -u root -sse "SELECT COUNT(*) FROM mysql.user WHERE User='${API_USER}' AND Host='localhost';" 2>/dev/null || echo "0")
else
    USER_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -sse "SELECT COUNT(*) FROM mysql.user WHERE User='${API_USER}' AND Host='localhost';" 2>/dev/null || echo "0")
fi

if [ "$USER_EXISTS" -gt 0 ]; then
    print_status "User '${API_USER}'@'localhost' exists in MySQL"
else
    print_warning "User '${API_USER}'@'localhost' does NOT exist in MySQL"
fi
echo

# Step 3: Test current credentials if they exist
if [ -n "$CURRENT_PASSWORD" ] && [ "$USER_EXISTS" -gt 0 ]; then
    print_step "Step 3: Testing current credentials..."
    if mysql -u "${API_USER}" -p"${CURRENT_PASSWORD}" -e "USE ${DB_NAME}; SELECT 1;" >/dev/null 2>&1; then
        print_status "Current credentials work! No fix needed."
        
        # Test SELECT permission
        RECORD_COUNT=$(mysql -u "${API_USER}" -p"${CURRENT_PASSWORD}" -D "${DB_NAME}" -sse "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null || echo "0")
        print_status "Can read ${RECORD_COUNT} records from remote_logs table"
        
        echo
        print_status "Everything is working correctly!"
        echo
        echo "API User: ${API_USER}"
        echo "Password: ${CURRENT_PASSWORD}"
        echo "Database: ${DB_NAME}"
        exit 0
    else
        print_error "Current credentials DO NOT work!"
        print_warning "Will recreate user with correct permissions..."
    fi
else
    print_warning "Cannot test current credentials (missing password or user)"
fi
echo

# Step 4: Generate new password
print_step "Step 4: Generating new secure password..."
NEW_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
print_status "New password generated: ${NEW_PASSWORD}"
echo

# Step 5: Drop and recreate user
print_step "Step 5: Recreating MySQL user with correct permissions..."

if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    mysql -u root << EOF
-- Drop user if exists
DROP USER IF EXISTS '${API_USER}'@'localhost';

-- Create user with new password
CREATE USER '${API_USER}'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';

-- Grant SELECT permission on the database
GRANT SELECT ON ${DB_NAME}.* TO '${API_USER}'@'localhost';

-- Flush privileges to ensure changes take effect
FLUSH PRIVILEGES;
EOF
else
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOF
-- Drop user if exists
DROP USER IF EXISTS '${API_USER}'@'localhost';

-- Create user with new password
CREATE USER '${API_USER}'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';

-- Grant SELECT permission on the database
GRANT SELECT ON ${DB_NAME}.* TO '${API_USER}'@'localhost';

-- Flush privileges to ensure changes take effect
FLUSH PRIVILEGES;
EOF
fi

print_status "User '${API_USER}'@'localhost' created successfully"
echo

# Step 6: Verify user creation
print_step "Step 6: Verifying user creation..."
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    USER_CHECK=$(mysql -u root -sse "SELECT User, Host FROM mysql.user WHERE User='${API_USER}' AND Host='localhost';" 2>/dev/null)
else
    USER_CHECK=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -sse "SELECT User, Host FROM mysql.user WHERE User='${API_USER}' AND Host='localhost';" 2>/dev/null)
fi

if [ -n "$USER_CHECK" ]; then
    print_status "User verified in mysql.user table"
else
    print_error "User NOT found in mysql.user table!"
    exit 1
fi
echo

# Step 7: Verify permissions
print_step "Step 7: Verifying user permissions..."
if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    PERMISSIONS=$(mysql -u root -sse "SHOW GRANTS FOR '${API_USER}'@'localhost';" 2>/dev/null)
else
    PERMISSIONS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -sse "SHOW GRANTS FOR '${API_USER}'@'localhost';" 2>/dev/null)
fi

echo "Permissions:"
echo "${PERMISSIONS}"
echo

if echo "${PERMISSIONS}" | grep -q "GRANT SELECT"; then
    print_status "SELECT permission verified"
else
    print_warning "SELECT permission not found in grants"
fi
echo

# Step 8: Test new credentials
print_step "Step 8: Testing new credentials..."
if mysql -u "${API_USER}" -p"${NEW_PASSWORD}" -e "USE ${DB_NAME}; SELECT COUNT(*) as count FROM remote_logs;" 2>&1 | grep -q "count"; then
    RECORD_COUNT=$(mysql -u "${API_USER}" -p"${NEW_PASSWORD}" -D "${DB_NAME}" -sse "SELECT COUNT(*) FROM remote_logs;" 2>/dev/null)
    print_status "Connection test PASSED! Found ${RECORD_COUNT} records"
else
    print_error "Connection test FAILED!"
    print_error "Testing failed with error:"
    mysql -u "${API_USER}" -p"${NEW_PASSWORD}" -e "USE ${DB_NAME}; SELECT 1;" 2>&1 || true
    exit 1
fi
echo

# Step 9: Update connection.php
print_step "Step 9: Updating connection.php with new credentials..."

# Backup existing file
if [ -f "/var/www/html/api/connection.php" ]; then
    cp /var/www/html/api/connection.php /var/www/html/api/connection.php.backup.$(date +%Y%m%d_%H%M%S)
    print_status "Backed up existing connection.php"
fi

# Create new connection.php
cat > /var/www/html/api/connection.php << 'PHPEOF'
<?php
/**
 * Database Connection Configuration
 * Separate connection file for security and modularity
 */

// Database configuration
define('DB_HOST', 'localhost');
define('DB_USER', 'syslog_api');
define('DB_PASS', 'REPLACE_PASSWORD_HERE');
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
            PDO::ATTR_EMULATE_PREPARES => false,
        ];
        
        $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
        $pdo->exec("SET NAMES utf8mb4");
        
        return $pdo;
    } catch (PDOException $e) {
        error_log("Database connection failed: " . $e->getMessage());
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
PHPEOF

# Replace password in file
sed -i "s/REPLACE_PASSWORD_HERE/${NEW_PASSWORD}/g" /var/www/html/api/connection.php

print_status "connection.php updated with new password"
echo

# Step 10: Test PHP connection
print_step "Step 10: Testing PHP PDO connection..."

cat > /tmp/test_connection.php << 'PHPTEST'
<?php
require_once '/var/www/html/api/connection.php';

echo "Testing connection...\n";
echo "DB_USER: " . DB_USER . "\n";
echo "DB_NAME: " . DB_NAME . "\n";

$pdo = getDBConnection();

if ($pdo) {
    echo "SUCCESS: Connected to database\n";
    
    $stmt = $pdo->query('SELECT COUNT(*) as count FROM remote_logs');
    $result = $stmt->fetch();
    echo "Record count: " . $result['count'] . "\n";
    
    // Test actual query
    $stmt = $pdo->query('SELECT id, hostname, message FROM remote_logs LIMIT 1');
    $record = $stmt->fetch();
    if ($record) {
        echo "Sample record ID: " . $record['id'] . "\n";
        echo "Sample hostname: " . $record['hostname'] . "\n";
    }
} else {
    echo "FAILED: Could not connect to database\n";
    exit(1);
}
?>
PHPTEST

PHP_TEST_RESULT=$(php /tmp/test_connection.php 2>&1)
rm -f /tmp/test_connection.php

if echo "$PHP_TEST_RESULT" | grep -q "SUCCESS"; then
    print_status "PHP PDO connection test PASSED"
    echo "$PHP_TEST_RESULT" | grep -E "(Record count|Sample)"
else
    print_error "PHP PDO connection test FAILED"
    echo "$PHP_TEST_RESULT"
    exit 1
fi
echo

# Step 11: Test API endpoint
print_step "Step 11: Testing API endpoint..."

# Restart Apache to ensure changes take effect
systemctl restart apache2
sleep 2

API_RESPONSE=$(curl -s -X POST http://localhost/api/api.php \
    -H "Content-Type: application/json" \
    -d '{"secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"}' 2>/dev/null)

if echo "$API_RESPONSE" | grep -q '"success": true'; then
    print_status "API endpoint test PASSED"
    RECORD_COUNT=$(echo "$API_RESPONSE" | grep -o '"count": [0-9]*' | grep -o '[0-9]*')
    print_status "API returned ${RECORD_COUNT} records"
else
    print_error "API endpoint test FAILED"
    echo "Response: $API_RESPONSE"
    exit 1
fi
echo

# Step 12: Save credentials
print_step "Step 12: Saving credentials..."

cat > /var/www/html/api/CREDENTIALS.txt << CREDEOF
========================================
  Remote Logs API - Access Credentials
========================================

DATABASE INFORMATION:
--------------------
Database Host: localhost
Database Name: ${DB_NAME}
Database User: ${API_USER}
Database Password: ${NEW_PASSWORD}

API INFORMATION:
---------------
API Secret Key: sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d
API Endpoint: http://$(hostname -I | awk '{print $1}')/api/api.php

TEST CONNECTION:
---------------
MySQL Command Line:
  mysql -u ${API_USER} -p'${NEW_PASSWORD}' ${DB_NAME}

Test Query:
  mysql -u ${API_USER} -p'${NEW_PASSWORD}' ${DB_NAME} -e "SELECT COUNT(*) FROM remote_logs;"

CURL TEST:
----------
curl -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d",
    "last_id": 0,
    "limit": 100
  }'

IMPORTANT:
----------
- Keep these credentials secure
- Delete this file after saving credentials elsewhere
- User has SELECT-only permissions (read-only)

Generated: $(date)
========================================
CREDEOF

chmod 600 /var/www/html/api/CREDENTIALS.txt
print_status "Credentials saved to: /var/www/html/api/CREDENTIALS.txt"
echo

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}         FIX COMPLETED SUCCESSFULLY!    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}Database User:${NC} ${API_USER}"
echo -e "${BLUE}New Password:${NC} ${NEW_PASSWORD}"
echo -e "${BLUE}Database:${NC} ${DB_NAME}"
echo -e "${BLUE}Records:${NC} ${RECORD_COUNT}"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. View credentials: cat /var/www/html/api/CREDENTIALS.txt"
echo "2. Test API: curl -X POST http://localhost/api/api.php -H 'Content-Type: application/json' -d '{\"secret_key\": \"sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d\"}'"
echo "3. Delete credentials file after saving: rm /var/www/html/api/CREDENTIALS.txt"
echo
print_status "All tests passed! Your API is ready to use."