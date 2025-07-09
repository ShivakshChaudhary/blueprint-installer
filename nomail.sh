#!/bin/bash

# Pterodactyl Panel Installation Script
# Official Documentation: https://pterodactyl.io/panel/1.0/getting_started.html
# This script automates the installation process for Ubuntu/Debian systems

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
PANEL_DOMAIN=""
MYSQL_PASSWORD=""
FQDN=""

# Default admin user credentials
PANEL_ADMIN_USERNAME="root"
PANEL_ADMIN_FIRST_NAME="root"
PANEL_ADMIN_LAST_NAME="user"
PANEL_ADMIN_PASSWORD="root"
PANEL_ADMIN_EMAIL="root@zylora.me"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}" 
    exit 1
fi

# Check for curl
if ! command -v curl &> /dev/null; then
    apt install -y curl
fi

# Welcome message
echo -e "${GREEN}"
cat << "EOF"
Pterodactyl Panel Installation Script
This will install Pterodactyl Panel with all dependencies, MySQL, Redis, Nginx, and PHP 8.3
EOF
echo -e "${NC}"

# Collect user input
read -p "Enter your domain name (e.g., panel.example.com): " PANEL_DOMAIN
read -p "Enter a password for the MySQL pterodactyl user: " MYSQL_PASSWORD
FQDN=$PANEL_DOMAIN

# Verify FQDN
if [[ -z "$FQDN" ]]; then
    echo -e "${RED}FQDN cannot be empty. Exiting.${NC}"
    exit 1
fi

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt update && apt upgrade -y

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

# Add PHP repository
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

# Add Redis repository
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list

# Update repositories
apt update

# Install packages
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Install composer
echo -e "${YELLOW}Installing Composer...${NC}"
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Create SSL certificates
echo -e "${YELLOW}Creating SSL certificates...${NC}"
mkdir -p /etc/certs
cd /etc/certs
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=NA/ST=NA/L=NA/O=NA/CN=${FQDN}" -keyout privkey.pem -out fullchain.pem

# Configure database
echo -e "${YELLOW}Configuring database...${NC}"
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -u root -e "CREATE DATABASE panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

# Download and configure panel
echo -e "${YELLOW}Downloading and configuring Pterodactyl Panel...${NC}"
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# Configure environment
php artisan p:environment:setup \
    --author=$PANEL_ADMIN_EMAIL \
    --url=https://$FQDN \
    --timezone=UTC \
    --cache=redis \
    --session=redis \
    --queue=redis \
    --redis-host=127.0.0.1 \
    --redis-pass= \
    --redis-port=6379

php artisan p:environment:database \
    --host=127.0.0.1 \
    --port=3306 \
    --database=panel \
    --username=pterodactyl \
    --password=$MYSQL_PASSWORD

# Skip SMTP configuration and set mail driver to log
echo -e "${YELLOW}Skipping SMTP configuration, setting mail driver to log...${NC}"
sed -i 's/^MAIL_DRIVER=.*/MAIL_DRIVER=log/' /var/www/pterodactyl/.env
sed -i 's/^MAIL_FROM=.*/MAIL_FROM="'"$PANEL_ADMIN_EMAIL"'"/' /var/www/pterodactyl/.env
sed -i 's/^MAIL_FROM_NAME=.*/MAIL_FROM_NAME="Pterodactyl Panel"/' /var/www/pterodactyl/.env

# Run migrations and seeds
echo -e "${YELLOW}Running database migrations...${NC}"
php artisan migrate --seed --force

# Create admin user
echo -e "${YELLOW}Creating admin user...${NC}"
php artisan p:user:make \
    --email=$PANEL_ADMIN_EMAIL \
    --username=$PANEL_ADMIN_USERNAME \
    --name-first=$PANEL_ADMIN_FIRST_NAME \
    --name-last=$PANEL_ADMIN_LAST_NAME \
    --password=$PANEL_ADMIN_PASSWORD \
    --admin=1

# Set permissions
chown -R www-data:www-data /var/www/pterodactyl/*

# Configure cron
echo -e "${YELLOW}Configuring cron job...${NC}"
(crontab -l ; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

# Configure queue worker
echo -e "${YELLOW}Configuring queue worker...${NC}"
cat > /etc/systemd/system/pteroq.service <<- 'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq.service
systemctl enable --now redis-server

# Configure Nginx
echo -e "${YELLOW}Configuring Nginx...${NC}"
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/pterodactyl.conf <<- EOF
server {
    listen 80;
    server_name $FQDN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $FQDN;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    ssl_certificate /etc/certs/fullchain.pem;
    ssl_certificate_key /etc/certs/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx

# Installation complete
echo -e "${GREEN}"
cat << "EOF"
Pterodactyl Panel has been successfully installed!

Default admin credentials:
Username: root
Password: root
Email: root@zylora.me

You can access your panel at: https://yourdomain.com

WARNING: For security reasons, you should:
1. Change the default admin password immediately
2. Consider creating additional admin users
3. Disable or delete the default root account if not needed

NOTE: Email sending is disabled (set to log driver)
To configure email later, edit your .env file

Next steps:
1. Install Wings on your game servers
2. Configure your panel settings
3. Add your first server location

For more information, visit: https://pterodactyl.io
EOF
echo -e "${NC}"

echo -e "${GREEN}Panel URL: https://${FQDN}${NC}"
echo -e "${GREEN}Admin Username: ${PANEL_ADMIN_USERNAME}${NC}"
echo -e "${GREEN}Admin Password: ${PANEL_ADMIN_PASSWORD}${NC}"
echo -e "${GREEN}Admin Email: ${PANEL_ADMIN_EMAIL}${NC}"