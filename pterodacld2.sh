#!/bin/bash

# Pterodactyl Panel Auto-Installer
# Version 1.0
# Simplified version without Wings and Cloudflare

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Welcome message
echo -e "${GREEN}"
cat << "EOF"
 ____            _                  _       _          _ 
|  _ \ ___  _ __| |_ ___  _ __ ___ | | __ _| |_ __  __| |
| |_) / _ \| '__| __/ _ \| '_ ` _ \| |/ _` | | '_ \/ _` |
|  __/ (_) | |  | || (_) | | | | | | | (_| | | | | | (_| |
|_|   \___/|_|   \__\___/|_| |_| |_|_|\__,_|_|_| |_|\__,_|
EOF
echo -e "${NC}"
echo -e "${YELLOW}Pterodactyl Panel Auto-Installer${NC}"
echo -e "${BLUE}------------------------------------------------${NC}"

# Function to handle errors
handle_error() {
  echo -e "${RED}Error: $1${NC}"
  echo -e "${YELLOW}Check the logs at /var/log/pterodactyl-installer.log for details.${NC}"
  exit 1
}

# Update system and install dependencies
echo -e "${BLUE}[1/4] Updating system and installing dependencies...${NC}"
apt update && apt upgrade -y || handle_error "Failed to update system packages"
apt install -y curl openssl nginx mariadb-server php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} || handle_error "Failed to install dependencies"

# Run Pterodactyl installer
echo -e "${BLUE}[2/4] Running Pterodactyl installer...${NC}"

# Ask for domain/subdomain
read -p "Enter your panel domain/subdomain (e.g., panel.yourdomain.com): " PANEL_DOMAIN

# Ask for SSL configuration
read -p "Do you want to use Let's Encrypt for HTTPS? (y/n): " USE_LE
if [[ $USE_LE =~ ^[Yy]$ ]]; then
  USE_LE="y"
  ASSUME_SSL="y"
  AGREE_HTTPS="y"
else
  USE_LE="n"
  ASSUME_SSL="y"
  AGREE_HTTPS="n"
fi

# Ask for UFW
read -p "Do you want to configure UFW firewall? (y/n): " USE_UFW
if [[ $USE_UFW =~ ^[Yy]$ ]]; then
  USE_UFW="y"
else
  USE_UFW="n"
fi

# Run the installer with selected options
echo -e "${YELLOW}Starting Pterodactyl installation with the following options:${NC}"
echo -e "Domain: ${GREEN}$PANEL_DOMAIN${NC}"
echo -e "UFW: ${GREEN}$USE_UFW${NC}"
echo -e "Let's Encrypt: ${GREEN}$USE_LE${NC}"
echo -e "Assume SSL: ${GREEN}$ASSUME_SSL${NC}"
echo -e "Agree HTTPS: ${GREEN}$AGREE_HTTPS${NC}"

bash <(curl -s https://pterodactyl-installer.se) <<EOF
$PANEL_DOMAIN
$USE_UFW
$USE_LE
$ASSUME_SSL
$AGREE_HTTPS
EOF

[ $? -ne 0 ] && handle_error "Pterodactyl panel installation failed"

# Configure SSL if not using Let's Encrypt
if [[ $USE_LE =~ ^[Nn]$ ]]; then
  echo -e "${BLUE}[3/4] Configuring self-signed SSL certificates...${NC}"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /2.pem -out /1.pem -subj "/CN=localhost" || handle_error "Failed to generate SSL certificates"
  
  # Configure Nginx
  sed -i 's|^\s*ssl_certificate\s\+.*|    ssl_certificate /1.pem;|' /etc/nginx/sites-available/pterodactyl.conf || handle_error "Failed to update Nginx SSL certificate path"
  sed -i 's|^\s*ssl_certificate_key\s\+.*|    ssl_certificate_key /2.pem;|' /etc/nginx/sites-available/pterodactyl.conf || handle_error "Failed to update Nginx SSL key path"
  sed -i 's/\b443\b/8443/g; s/\b80\b/8000/g' /etc/nginx/sites-available/pterodactyl.conf || handle_error "Failed to update Nginx ports"
  
  systemctl restart nginx || handle_error "Failed to restart Nginx"
fi

# Completion message
echo -e "${BLUE}[4/4] Installation completed!${NC}"
echo -e "${GREEN}"
cat << "EOF"
 ____            _      _       _ 
|  _ \ ___  _ __| |_ __| |   __| |
| |_) / _ \| '__| __/ _` |  / _` |
|  __/ (_) | |  | || (_| | | (_| |
|_|   \___/|_|   \__\__,_|  \__,_|
EOF
echo -e "${NC}"
echo -e "${GREEN}Pterodactyl Panel installation completed successfully!${NC}"
echo -e ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Access your panel at: ${GREEN}https://$PANEL_DOMAIN${NC}"
echo -e "2. Create your first admin account"
echo -e ""
echo -e "${BLUE}Need help? Check these resources:${NC}"
echo -e "- Official Documentation: ${GREEN}https://pterodactyl.io${NC}"
echo -e "- Community Support: ${GREEN}https://discord.gg/pterodactyl${NC}"