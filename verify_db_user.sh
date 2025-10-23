#!/bin/bash

# Script to verify database user permissions for the syslog collector API

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

# Start
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} Database User Verification Script   ${NC}"
echo -e "${GREEN}====================================${NC}"
echo

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    print_warning "This script should be run as root for full verification"
    print_warning "Some checks may fail without root privileges"
    echo
fi

# Extract database configuration from connection.php
print_step "Extracting database configuration..."
if [ ! -f "connection.php" ]; then
    print_error "connection.php not found in current directory"
    exit 1
fi

DB_USER=$(grep "define('DB_USER'" connection.php | cut -d"'" -f4)
DB_PASS=$(grep "define('DB_PASS'" connection.php | cut -d"'" -f4)
DB_NAME=$(grep "define('DB_NAME'" connection.php | cut -d"'" -f4)

print_status "Database user: $DB_USER"
print_status "Database name: $DB_NAME"
echo

# Check if user exists
print_step "Checking if database user exists..."
if mysql -u root -e "SELECT User, Host FROM mysql.user WHERE User='$DB_USER';" >/dev/null 2>&1; then
    print_status "Database user '$DB_USER' exists"
else
    print_error "Database user '$DB_USER' does not exist"
    exit 1
fi
echo

# Check user permissions
print_step "Checking user permissions..."
PERMISSIONS=$(mysql -u root -e "SHOW GRANTS FOR '$DB_USER'@'localhost';" 2>/dev/null || echo "No permissions found")
echo "$PERMISSIONS"
echo

# Test connection with API user
print_step "Testing database connection with API user..."
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT COUNT(*) as count FROM remote_logs;" >/dev/null 2>&1; then
    print_status "Successfully connected to database with API user"
    
    # Count records
    RECORD_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT COUNT(*) FROM remote_logs;")
    print_status "Record count in remote_logs table: $RECORD_COUNT"
else
    print_error "Failed to connect to database with API user"
    print_error "DB_USER: $DB_USER"
    print_error "DB_NAME: $DB_NAME"
    print_error "Password length: ${#DB_PASS} characters"
    
    # Check if user exists
    USER_EXISTS=$(mysql -u root -e "SELECT User FROM mysql.user WHERE User='$DB_USER';" 2>/dev/null | wc -l)
    if [ "$USER_EXISTS" -gt 1 ]; then
        print_status "User $DB_USER exists in MySQL"
    else
        print_error "User $DB_USER does not exist in MySQL"
    fi
    
    # Check user permissions
    print_step "Checking user permissions..."
    mysql -u root -e "SHOW GRANTS FOR '$DB_USER'@'localhost';" 2>/dev/null || print_error "Could not retrieve user permissions"
    
    exit 1
fi
echo

# Test PDO connection
print_step "Testing PDO connection..."
PDO_TEST=$(php -r "
require_once 'connection.php';
\$pdo = getDBConnection();
if (\$pdo) {
    \$stmt = \$pdo->query('SELECT COUNT(*) as count FROM remote_logs');
    \$result = \$stmt->fetch();
    echo 'SUCCESS:' . \$result['count'];
} else {
    echo 'FAILED';
}
" 2>&1)

if [[ "$PDO_TEST" == SUCCESS:* ]]; then
    RECORD_COUNT=${PDO_TEST#SUCCESS:}
    print_status "PDO connection successful ($RECORD_COUNT records found)"
else
    print_error "PDO connection failed"
    print_error "Error: $PDO_TEST"
fi
echo

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} Database User Verification Complete  ${NC}"
echo -e "${GREEN}====================================${NC}"
if [[ "$PDO_TEST" == SUCCESS:* ]]; then
    print_status "All checks passed! The API should work correctly."
else
    print_error "Some checks failed. Please review the errors above."
    exit 1
fi