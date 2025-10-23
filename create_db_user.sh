#!/bin/bash

# Script to manually create the database user for the syslog collector API

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
API_USER="syslog_api"
API_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)

# Start
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} Database User Creation Script       ${NC}"
echo -e "${GREEN}====================================${NC}"
echo

print_step "Creating database user with the following credentials:"
echo "Database name: $DB_NAME"
echo "User name: $API_USER"
echo "Password: $API_PASSWORD"
echo

# Check if running as root
if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
    print_warning "This script should be run with sudo privileges"
    print_warning "Some operations may fail without proper permissions"
    echo
fi

# Create the user
print_step "Creating database user..."
mysql -u root << EOF
DROP USER IF EXISTS '${API_USER}'@'localhost';
CREATE USER '${API_USER}'@'localhost' IDENTIFIED BY '${API_PASSWORD}';
GRANT SELECT ON ${DB_NAME}.* TO '${API_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

print_status "Database user created successfully"

# Verify user creation
print_step "Verifying user creation..."
USER_EXISTS=$(mysql -u root -e "SELECT User FROM mysql.user WHERE User='${API_USER}';" 2>/dev/null | wc -l)
if [ "$USER_EXISTS" -gt 1 ]; then
    print_status "User verification successful"
else
    print_error "User verification failed"
    exit 1
fi

# Show user permissions
print_step "User permissions:"
mysql -u root -e "SHOW GRANTS FOR '${API_USER}'@'localhost';"

# Update connection.php with new credentials
print_step "Updating connection.php..."
API_DIR="/var/www/html/api"
if [ -f "$API_DIR/connection.php" ]; then
    # Create backup
    cp "$API_DIR/connection.php" "$API_DIR/connection.php.backup"
    
    # Update the file
    sed -i "s/define('DB_USER', '[^']*')/define('DB_USER', '${API_USER}')/g" "$API_DIR/connection.php"
    sed -i "s/define('DB_PASS', '[^']*')/define('DB_PASS', '${API_PASSWORD}')/g" "$API_DIR/connection.php"
    
    print_status "connection.php updated successfully"
else
    print_warning "connection.php not found at $API_DIR/connection.php"
    print_warning "You may need to update it manually"
fi

echo
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} Database User Creation Complete     ${NC}"
echo -e "${GREEN}====================================${NC}"
echo
print_status "Database user: $API_USER"
print_status "Database password: $API_PASSWORD"
print_status "Database name: $DB_NAME"
echo
print_status "The syslog collector API should now work correctly."