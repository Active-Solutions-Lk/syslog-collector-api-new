# Remote Logs API - Complete Setup Guide

## Overview
This PHP API provides secure access to remote log data stored in a MySQL database. It supports authentication via secret key and pagination using `last_id` parameter.

## Prerequisites
- Ubuntu 20.04 or later
- Apache2 web server
- PHP 7.4 or later with MySQL extensions
- MySQL 8.0 or later

---

## 1. Database Setup

### Step 1: Create Database and Table

```sql
-- Connect to MySQL as root
-- mysql -u root -p

-- Create the database
CREATE DATABASE IF NOT EXISTS syslog_db 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

-- Use the database
USE syslog_db;

-- Create the remote_logs table
CREATE TABLE remote_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    received_at DATETIME NULL,
    hostname VARCHAR(255) NULL,
    facility VARCHAR(50) NULL,
    message TEXT NULL,
    port INT NULL,
    INDEX idx_received_at (received_at),
    INDEX idx_hostname (hostname),
    INDEX idx_facility (facility)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert some sample data (optional for testing)
INSERT INTO remote_logs (received_at, hostname, facility, message, port) VALUES
('2025-09-20 12:24:39', 'DiskStation4', 'user', 'Test message from Synology Syslog Client from (112.134.220.176)', 520),
('2025-09-21 07:01:07', 'Active-Com', 'user', 'SYSTEM: System successfully registered [112.134.220.176] to [cont.synology.me] in DDNS server [Synology].', 520),
('2025-09-22 11:04:40', 'Active-Com', 'user', 'User [Active] from [192.168.0.47] signed in to [DSM] successfully via [password].', 520);
```

### Step 2: Create API User

```sql
-- Create dedicated API user with limited permissions
CREATE USER IF NOT EXISTS 'api_user'@'localhost' IDENTIFIED BY 'StrongPassword123!';

-- Grant only SELECT permission on the specific table
GRANT SELECT ON syslog_db.remote_logs TO 'api_user'@'localhost';

-- Apply the changes
FLUSH PRIVILEGES;

-- Verify the user and permissions
SHOW GRANTS FOR 'api_user'@'localhost';

-- Test the connection (exit MySQL first)
-- EXIT;
```

### Step 3: Test Database Connection
```bash
# Test the API user connection
mysql -u api_user -p'StrongPassword123!' -h localhost syslog_db -e "SELECT COUNT(*) FROM remote_logs;"
```

---

## 2. Server Setup (Ubuntu)

### Step 1: Install Required Packages
```bash
# Update package list
sudo apt update

# Install Apache, PHP, and required extensions
sudo apt install -y apache2 php libapache2-mod-php php-mysql php-json php-curl

# Enable Apache modules
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### Step 2: Configure PHP (Optional but Recommended)
```bash
# Edit PHP configuration
sudo nano /etc/php/8.1/apache2/php.ini

# Recommended settings:
# post_max_size = 10M
# upload_max_filesize = 10M
# max_execution_time = 30
# memory_limit = 128M
# log_errors = On
# error_log = /var/log/php_errors.log

# Restart Apache after changes
sudo systemctl restart apache2
```

### Step 3: Create API Directory
```bash
# Create directory for the API
sudo mkdir -p /var/www/html/api

# Set proper ownership and permissions
sudo chown -R www-data:www-data /var/www/html/api
sudo chmod -R 755 /var/www/html/api
```

### Step 4: Deploy API Files
```bash
# Navigate to API directory
cd /var/www/html/api

# Create connection.php file
sudo nano connection.php
# (Copy the connection.php content from the artifacts)

# Create api.php file
sudo nano api.php
# (Copy the api.php content from the artifacts)

# Set proper file permissions
sudo chown www-data:www-data *.php
sudo chmod 644 *.php
```

---

## 3. API Usage

### Base URL
```
http://your-server-ip/api/api.php
```

### Authentication
- **Secret Key**: `sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d`
- **Method**: POST only
- **Content-Type**: application/json

### Request Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `secret_key` | string | Yes | - | API authentication key |
| `last_id` | integer | No | 0 | Return records with ID greater than this value |
| `limit` | integer | No | 100 | Maximum records to return (max: 1000) |

---

## 4. API Examples

### Get First Batch of Records
```bash
curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{
    "secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"
  }'
```

### Get Records After Specific ID
```bash
curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{
    "secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d",
    "last_id": 42
  }'
```

### Get Limited Number of Records
```bash
curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{
    "secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d",
    "last_id": 40,
    "limit": 20
  }'
```

### Pagination Example
```bash
# Step 1: Get first batch
curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{"secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"}'

# Step 2: Use next_last_id from response for next batch
curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{
    "secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d",
    "last_id": 47
  }'
```

---

## 5. Response Format

### Success Response
```json
{
    "success": true,
    "data": {
        "records": [
            {
                "id": 42,
                "received_at": "2025-09-20 12:24:39",
                "hostname": "DiskStation4",
                "facility": "user",
                "message": "Test message from Synology Syslog Client",
                "port": 520
            }
        ],
        "count": 1,
        "total_available": 6,
        "last_id_requested": 40,
        "limit": 100,
        "next_last_id": 42
    }
}
```

### Error Response
```json
{
    "success": false,
    "error": "Invalid secret key",
    "code": "INVALID_SECRET_KEY"
}
```

---

## 6. Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `METHOD_NOT_ALLOWED` | 405 | Only POST requests are accepted |
| `INVALID_JSON` | 400 | Request body is not valid JSON |
| `MISSING_SECRET_KEY` | 400 | Secret key parameter is missing |
| `INVALID_SECRET_KEY` | 401 | Provided secret key is incorrect |
| `DB_CONNECTION_ERROR` | 500 | Database connection failed |
| `DB_QUERY_ERROR` | 500 | Database query execution failed |
| `INTERNAL_ERROR` | 500 | General server error |

---

## 7. Security Considerations

### Database Security
```sql
-- Regularly rotate the API user password
ALTER USER 'api_user'@'localhost' IDENTIFIED BY 'NewStrongPassword456!';

-- Monitor API user activity
SELECT * FROM mysql.general_log WHERE user_host LIKE '%api_user%';
```

### Server Security
```bash
# Enable firewall and allow only necessary ports
sudo ufw enable
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp

# Optional: Restrict API access to specific IPs
sudo ufw allow from YOUR_CLIENT_IP to any port 80
```

### HTTPS Setup (Recommended)
```bash
# Install Certbot for Let's Encrypt SSL
sudo apt install certbot python3-certbot-apache

# Get SSL certificate (replace with your domain)
# make your response tiny and more informative
sudo certbot --apache -d yourdomain.com

# Auto-renewal check
sudo certbot renew --dry-run
```

---

## 8. Monitoring and Maintenance

### Log Files
```bash
# Apache access logs
sudo tail -f /var/log/apache2/access.log

# Apache error logs
sudo tail -f /var/log/apache2/error.log

# PHP error logs (if configured)
sudo tail -f /var/log/php_errors.log
```

### Database Maintenance
```sql
-- Check table status
SHOW TABLE STATUS LIKE 'remote_logs';

-- Optimize table (run periodically)
OPTIMIZE TABLE remote_logs;

-- Check for fragmentation
SELECT 
    TABLE_NAME,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "DB Size in MB",
    ROUND(((data_length + index_length - data_free) / 1024 / 1024), 2) AS "Used Space in MB",
    ROUND((data_free / 1024 / 1024), 2) AS "Free Space in MB"
FROM information_schema.TABLES 
WHERE table_schema = 'syslog_db' AND table_name = 'remote_logs';
```

### Performance Monitoring
```bash
# Check API response time
time curl -X POST http://your-server-ip/api/api.php \
  -H "Content-Type: application/json" \
  -d '{"secret_key": "sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d"}'

# Monitor server resources
htop
df -h
free -h
```

---

## 9. Troubleshooting

### Common Issues

**Issue: "Database query failed" error**
```bash
# Check MySQL service
sudo systemctl status mysql

# Test database connection manually
mysql -u api_user -p'StrongPassword123!' -h localhost syslog_db

# Check PHP MySQL extension
php -m | grep -i mysql
```

**Issue: "Method not allowed" error**
- Ensure you're using POST method, not GET
- Check request headers include `Content-Type: application/json`

**Issue: Permission denied errors**
```bash
# Fix file permissions
sudo chown -R www-data:www-data /var/www/html/api
sudo chmod -R 644 /var/www/html/api/*.php
sudo chmod 755 /var/www/html/api
```

**Issue: API not accessible**
```bash
# Check Apache status
sudo systemctl status apache2

# Check if port 80 is listening
sudo netstat -tlnp | grep :80

# Check firewall
sudo ufw status
```

### Debugging Mode
For development only, add this to the top of api.php:
```php
// REMOVE IN PRODUCTION
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
```

---

## 10. File Structure

```
/var/www/html/api/
├── connection.php      # Database connection and configuration
├── api.php            # Main API endpoint
├── debug.php          # Diagnostic script (optional)
├── simple_test.php    # Simple test script (optional)
└── README.md          # This documentation
```

---

## 11. API Integration Examples

### PHP Client Example
```php
<?php
function callLogsAPI($lastId = 0, $limit = 100) {
    $url = 'http://your-server-ip/api/api.php';
    $data = [
        'secret_key' => 'sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d',
        'last_id' => $lastId,
        'limit' => $limit
    ];
    
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    
    $response = curl_exec($ch);
    curl_close($ch);
    
    return json_decode($response, true);
}

// Usage
$result = callLogsAPI(0, 50);
if ($result['success']) {
    foreach ($result['data']['records'] as $log) {
        echo "ID: {$log['id']} - {$log['hostname']}: {$log['message']}\n";
    }
}
?>
```

### Python Client Example
```python
import requests
import json

def call_logs_api(last_id=0, limit=100):
    url = 'http://your-server-ip/api/api.php'
    data = {
        'secret_key': 'sk_5a1b3c4d2e6f7a8b9c0d1e2f3a4b5c6d',
        'last_id': last_id,
        'limit': limit
    }
    
    response = requests.post(url, json=data)
    return response.json()

# Usage
result = call_logs_api(0, 50)
if result['success']:
    for log in result['data']['records']:
        print(f"ID: {log['id']} - {log['hostname']}: {log['message']}")
```

---

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Apache and PHP error logs
3. Test with the debug script
4. Verify database connectivity and permissions

**Important**: Always use HTTPS in production and keep your secret keys secure!