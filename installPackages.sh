#!/bin/bash

# Remote Logs API - Automated Installation Script (Updated)
# Uses MySQL root (with password) for API in secure environment
# Auto-detects PHP version, installs PDO driver, verifies everything
# Author: Updated for your secure setup
# Date: $(date)

set -e  # Exit on any error

# ------------------- Colors -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------- Config -------------------
DB_NAME="syslog_db"
API_SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
API_DIR="/var/www/html/api"

# === USER INPUT: Set your MySQL root password ===
read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "${RED}[ERROR] Root password cannot be empty.${NC}"
    exit 1
fi
export MYSQL_ROOT_PASSWORD

# ------------------- Functions -------------------
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_mysql_service() { systemctl is-active --quiet mysql; }
database_exists() { mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "USE ${DB_NAME};" >/dev/null 2>&1; }
table_exists() { mysql -u root -p"$MYSQL_ROOT_PASSWORD" -D "${DB_NAME}" -e "DESCRIBE remote_logs;" >/dev/null 2>&1; }

# ------------------- Start -------------------
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Remote Logs API Installation   ${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Step 1: Update system
print_step "Updating system packages..."
apt update -y

# Step 2: Install Apache
print_step "Installing Apache2..."
if command_exists apache2; then
    print_warning "Apache2 already installed"
else
    apt install -y apache2
fi
systemctl enable apache2
systemctl start apache2

# Step 3: Install PHP (auto-detect Ubuntu default)
print_step "Installing PHP (Ubuntu default version)..."
apt install -y php libapache2-mod-php

# Detect actual PHP version
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
print_status "Detected PHP version: $PHP_VER"

# Step 4: Install PDO MySQL driver
print_step "Installing PHP MySQL driver (PDO)..."
apt install -y php${PHP_VER}-mysql

# Restart Apache to load new PHP module
print_step "Restarting Apache to load PHP + PDO..."
systemctl restart apache2

# Step 5: Verify PDO is available
print_step "Verifying PDO MySQL driver..."
if php -r "exit(in_array('mysql', PDO::getAvailableDrivers()) ? 0 : 1);" 2>/dev/null; then
    print_status "PDO MySQL driver: OK"
else
    print_error "PDO MySQL driver failed to load!"
    exit 1
fi

# Step 6: Create API directory
print_step "Creating API directory..."
mkdir -p "$API_DIR"
chown www-data:www-data "$API_DIR"

# Step 7: Write connection.php (uses root + password)
print_step "Writing connection.php with root credentials..."
cat > "$API_DIR/connection.php" << EOF
<?php
/**
 * Database Connection using MySQL root (secure environment)
 */
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '$MYSQL_ROOT_PASSWORD');
define('DB_NAME', '$DB_NAME');

define('API_SECRET_KEY', '$API_SECRET_KEY');

function getDBConnection() {
    try {
        \$dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4";
        \$options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ];
        \$pdo = new PDO(\$dsn, DB_USER, DB_PASS, \$options);
        \$pdo->exec("SET NAMES utf8mb4");
        return \$pdo;
    } catch (Exception \$e) {
        error_log("DB Connection failed: " . \$e->getMessage());
        return null;
    }
}

function validateAPIKey(\$key) {
    return hash_equals(API_SECRET_KEY, \$key);
}
?>
EOF

# Step 8: Write api.php (simple log fetcher)
print_step "Writing api.php..."
cat > "$API_DIR/api.php" << 'EOF'
<?php
require_once 'connection.php';

header('Content-Type: application/json');

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || !validateAPIKey($input['secret_key'] ?? '')) {
    echo json_encode(['success' => false, 'message' => 'Invalid key']);
    exit;
}

$pdo = getDBConnection();
if (!$pdo) {
    echo json_encode(['success' => false, 'message' => 'DB error']);
    exit;
}

$limit = min(1000, (int)($input['limit'] ?? 100));
$last_id = (int)($input['last_id'] ?? 0);

$sql = "SELECT * FROM remote_logs WHERE id > :last_id ORDER BY id ASC LIMIT :limit";
$stmt = $pdo->prepare($sql);
$stmt->bindValue(':last_id', $last_id, PDO::PARAM_INT);
$stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
$stmt->execute();

$logs = $stmt->fetchAll();
echo json_encode([
    'success' => true,
    'data' => $logs,
    'count' => count($logs),
    'next_id' => $logs ? end($logs)['id'] : $last_id
]);
?>
EOF

# Step 9: Create test script
print_step "Creating test script..."
cat > "$API_DIR/test_api.sh" << EOF
#!/bin/bash
echo "Testing API..."
curl -s -X POST http://localhost/api/api.php \\
  -H "Content-Type: application/json" \\
  -d '{
    "secret_key": "$API_SECRET_KEY",
    "limit": 2
  }' | jq .
EOF
chmod +x "$API_DIR/test_api.sh"

# Step 10: Final verification
print_step "Final system check..."
OK=true

systemctl is-active --quiet apache2 || { print_error "Apache2 not running"; OK=false; }
check_mysql_service || { print_error "MySQL not running"; OK=false; }
database_exists && table_exists || { print_error "Database/table missing"; OK=false; }

if [ "$OK" = true ]; then
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}   INSTALLATION SUCCESSFUL!     ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
    print_status "API: http://$(hostname -I | awk '{print $1}')/api/api.php"
    print_status "Secret Key: $API_SECRET_KEY"
    print_status "Test: bash $API_DIR/test_api.sh"
else
    echo -e "${RED}INSTALLATION FAILED${NC}"
    exit 1
fi