#!/bin/bash

# Script to fix PHP PDO MySQL module issues
# This script checks for and installs the required PHP modules for the syslog collector API

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
echo -e "${GREEN} PHP PDO MySQL Module Fix Script    ${NC}"
echo -e "${GREEN}====================================${NC}"
echo

# Detect PHP version
print_step "Detecting PHP version..."
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "7.4")
print_status "Detected PHP version: $PHP_VERSION"

# Check current modules
print_step "Checking currently installed PHP modules..."
echo "PDO modules:"
php -m | grep -i pdo || echo "No PDO modules found"
echo "MySQL modules:"
php -m | grep -i mysql || echo "No MySQL modules found"

# Check available PDO drivers
print_step "Checking available PDO drivers..."
PDO_DRIVERS=$(php -r "print_r(PDO::getAvailableDrivers());" 2>/dev/null || echo "None")
echo "Available PDO drivers: $PDO_DRIVERS"

# Install required packages
print_step "Installing required PHP packages..."
REQUIRED_PACKAGES="php$PHP_VERSION-mysql php$PHP_VERSION-pdo"

for package in $REQUIRED_PACKAGES; do
    print_status "Installing $package..."
    apt install -y $package >/dev/null 2>&1 || {
        print_error "Failed to install $package"
        exit 1
    }
done

print_status "Required packages installed successfully"

# Enable PHP modules
print_step "Enabling PHP modules..."
phpenmod pdo pdo_mysql mysqlnd 2>/dev/null || {
    print_warning "Some modules could not be enabled automatically"
    print_warning "You may need to enable them manually"
}

# Restart Apache
print_step "Restarting Apache to load new modules..."
systemctl restart apache2 || {
    print_error "Failed to restart Apache"
    exit 1
}

print_status "Apache restarted successfully"

# Verify installation
print_step "Verifying installation..."
echo "PDO modules after installation:"
php -m | grep -i pdo || echo "No PDO modules found"
echo "MySQL modules after installation:"
php -m | grep -i mysql || echo "No MySQL modules found"

# Check available PDO drivers again
print_step "Checking available PDO drivers after installation..."
PDO_DRIVERS=$(php -r "print_r(PDO::getAvailableDrivers());" 2>/dev/null || echo "None")
echo "Available PDO drivers: $PDO_DRIVERS"

if echo "$PDO_DRIVERS" | grep -q "mysql"; then
    print_status "PDO MySQL driver is now available!"
    print_status "The syslog collector API should now work correctly."
else
    print_error "PDO MySQL driver is still not available."
    print_error "Manual intervention may be required."
    exit 1
fi

echo
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} PHP PDO MySQL Module Fix Complete  ${NC}"
echo -e "${GREEN}====================================${NC}"
echo
print_status "The syslog collector API should now work correctly."
print_status "You can test it by running: php simple_test.php"