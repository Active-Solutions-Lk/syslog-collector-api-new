#!/bin/bash

# Quick Installation Script for Remote Logs API
# This script performs only the essential installation steps

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Configuration
DB_NAME="syslog_db"
API_SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
API_DIR="/var/www/html/api"

# Start
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Quick Remote Logs API Install  ${NC}"
echo -e "${GREEN}================================${NC}"
echo

print_step "Checking system requirements..."
# Check if required commands exist
for cmd in systemctl mysql php; do
    if ! command -v $cmd >/dev/null 2>&1; then
        print_error "$cmd is not installed"
        exit 1
    fi
done
print_status "All required commands are available"

# Check services
print_step "Checking services..."
if systemctl is-active --quiet apache2; then
    print_status "Apache2 is running"
else
    print_error "Apache2 is not running"
    exit 1
fi

if systemctl is-active --quiet mysql; then
    print_status "MySQL is running"
else
    print_error "MySQL is not running"
    exit 1
fi

# Create database user
print_step "Setting up database user..."
API_USER="syslog_api"
API_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)

mysql -u root << EOF
CREATE USER IF NOT EXISTS '${API_USER}'@'localhost' IDENTIFIED BY '${API_PASSWORD}';
GRANT SELECT ON ${DB_NAME}.* TO '${API_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

print_status "Database user created: $API_USER"

# Create connection.php
print_step "Creating connection.php..."
mkdir -p "$API_DIR"

cat > "$API_DIR/connection.php" << EOF
<?php
/**
 * Database Connection Configuration
 * Separate connection file for security and modularity
 */

// Database configuration
define('DB_HOST', 'localhost');
define('DB_USER', '${API_USER}');
define('DB_PASS', '${API_PASSWORD}');
define('DB_NAME', '${DB_NAME}');

// Secret key for API authentication
define('API_SECRET_KEY', '${API_SECRET_KEY}');

/**
 * Get database connection
 * @return PDO|null
 */
function getDBConnection() {
    try {
        \$dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        \$options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false
        ];
        
        // Only add MYSQL_ATTR_INIT_COMMAND if it's defined
        if (defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
            \$options[PDO::MYSQL_ATTR_INIT_COMMAND] = "SET NAMES utf8mb4";
        }
        
        \$pdo = new PDO(\$dsn, DB_USER, DB_PASS, \$options);
        
        // If the constant wasn't defined, set the charset manually
        if (!defined('PDO::MYSQL_ATTR_INIT_COMMAND')) {
            \$pdo->exec("SET NAMES utf8mb4");
        }
        
        return \$pdo;
    } catch (PDOException \$e) {
        error_log("Database connection failed: " . \$e->getMessage());
        return null;
    } catch (Exception \$e) {
        error_log("General error during database connection: " . \$e->getMessage());
        return null;
    }
}

/**
 * Validate API secret key
 * @param string \$providedKey
 * @return bool
 */
function validateAPIKey(\$providedKey) {
    return hash_equals(API_SECRET_KEY, \$providedKey);
}
?>
EOF

print_status "connection.php created successfully"

# Copy API files
print_step "Copying API files..."
cp api.php "$API_DIR/"
cp simple_test.php "$API_DIR/"
print_status "API files copied"

# Set permissions
print_step "Setting file permissions..."
chown -R www-data:www-data "$API_DIR"
chmod -R 644 "$API_DIR"/*.php
chmod 755 "$API_DIR"
print_status "File permissions set"

# Restart Apache
print_step "Restarting Apache..."
systemctl restart apache2
print_status "Apache restarted"

# Test connection
print_step "Testing database connection..."
DB_TEST_RESULT=$(php -r "
require_once '$API_DIR/connection.php';
\$pdo = getDBConnection();
if (\$pdo) {
    echo 'SUCCESS';
} else {
    echo 'FAILED';
}
" 2>/dev/null)

if [[ "$DB_TEST_RESULT" == "SUCCESS" ]]; then
    print_status "Database connection test passed"
else
    print_error "Database connection test failed"
    exit 1
fi

echo
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}   QUICK INSTALLATION COMPLETE  ${NC}"
echo -e "${GREEN}================================${NC}"
echo
print_status "API Endpoint: http://$(hostname -I | awk '{print $1}')/api/api.php"
print_status "Secret Key: ${API_SECRET_KEY}"
print_status "Database User: ${API_USER}"
print_status "Database: ${DB_NAME}"
echo
print_status "Test with: php simple_test.php"