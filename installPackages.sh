#!/bin/bash

# Remote Logs API - FINAL VERSION
# Uses Admin / Admin@collector1 (from syslog collector)
# No password prompt, auto PHP + PDO, clean install
# Path: /var/www/html/api/

set -e

# ------------------- Colors -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------- Fixed Config -------------------
DB_NAME="syslog_db"
DB_USER="Admin"
DB_PASS="Admin@collector1"
API_SECRET_KEY="sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
API_DIR="/var/www/html/api"

# ------------------- Functions -------------------
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ------------------- Start -------------------
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN} Remote Logs API - FINAL SETUP  ${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Step 1: Update system
print_step "Updating package list..."
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

# Step 3: Install PHP (Ubuntu default)
print_step "Installing PHP + Apache module..."
apt install -y php libapache2-mod-php

# Detect PHP version
PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.1")
print_status "PHP Version: $PHP_VER"

# Step 4: Install PDO MySQL driver
print_step "Installing php${PHP_VER}-mysql (PDO driver)..."
apt install -y php${PHP_VER}-mysql

# Restart Apache
print_step "Restarting Apache..."
systemctl restart apache2

# Step 5: Verify PDO
print_step "Verifying PDO MySQL driver..."
if php -r "exit(in_array('mysql', PDO::getAvailableDrivers()) ? 0 : 1);" 2>/dev/null; then
    print_status "PDO MySQL: OK"
else
    print_error "PDO MySQL failed!"
    exit 1
fi

# Step 6: Clean old API folder (prevent duplicates)
print_step "Removing old API folder (if exists)..."
rm -rf /var/www/html/syslog-collector-api-new 2>/dev/null || true

# Step 7: Create API directory
print_step "Creating API directory: $API_DIR"
mkdir -p "$API_DIR"
chown www-data:www-data "$API_DIR"

# Step 8: Write connection.php (Admin user)
print_step "Writing connection.php (using Admin user)..."
cat > "$API_DIR/connection.php" << EOF
<?php
/**
 * Secure connection using Admin@collector1
 */
define('DB_HOST', 'localhost');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');
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
        error_log("DB Error: " . \$e->getMessage());
        return null;
    }
}

function validateAPIKey(\$key) {
    return hash_equals(API_SECRET_KEY, \$key);
}
?>
EOF

# Step 9: Write api.php
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

# Step 10: Create test script
print_step "Creating test script..."
cat > "$API_DIR/test_api.sh" << EOF
#!/bin/bash
echo "Testing API..."
curl -s -X POST http://localhost/api/api.php \
  -H "Content-Type: application/json" \
  -d '{
    "secret_key": "$API_SECRET_KEY",
    "limit": 2
  }' | jq .
EOF
chmod +x "$API_DIR/test_api.sh"

# Final Check
print_step "Final verification..."
OK=true

systemctl is-active --quiet apache2 || { print_error "Apache down"; OK=false; }
mysql -u Admin -p'Admin@collector1' -e "USE syslog_db;" >/dev/null 2>&1 || { print_error "DB login failed"; OK=false; }

if [ "$OK" = true ]; then
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}   SUCCESS: API READY!          ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
    print_status "URL: http://$(hostname -I | awk '{print $1}')/api/api.php"
    print_status "Test: bash $API_DIR/test_api.sh"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi