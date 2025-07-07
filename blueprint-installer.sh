#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Branding and Credits
BRAND="\n${PURPLE}
╔═══════════════════════════════════════════════════╗
║  ____  _                       _       _    
║ | __ )| |_   _  ___ _ __  _ __(_)_ __ | |_  
║ |  _ \| | | | |/ _ \ '_ \| '__| | '_ \| __| 
║ | |_) | | |_| |  __/ |_) | |  | | | | | |_  
║ |____/|_|\__,_|\___| .__/|_|  |_|_| |_|\__| 
║                    |_|                      
║      ${YELLOW}>> made by Shivaksh Chaudhary <<${PURPLE}    ║
║         ${YELLOW}DC: unbelievablegirl.exe${PURPLE}         ║
╚═══════════════════════════════════════════════════╝${NC}"

CREDITS="\n${YELLOW}Created by: Shivaksh Chaudhary
Discord: unbelievablegirl.exe${NC}\n"

# Display branding and credits
echo -e "$BRAND"
echo -e "$CREDITS"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}" >&2
   exit 1
fi

# Verify Pterodactyl installation
PTERODACTYL_PATH="/var/www/pterodactyl"
if [ ! -d "$PTERODACTYL_PATH" ]; then
    echo -e "${RED}Error: Pterodactyl installation not found at $PTERODACTYL_PATH${NC}"
    echo -e "Please install Pterodactyl first or specify the correct path"
    exit 1
fi

echo -e "${GREEN}[*] Installing Node.js v20...${NC}"
# Install Node.js v20
sudo apt-get install -y ca-certificates curl gnupg > /dev/null
sudo mkdir -p /etc/apt/keyrings > /dev/null
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
apt-get update > /dev/null
apt-get install -y nodejs > /dev/null

echo -e "${GREEN}[*] Installing Yarn...${NC}"
npm i -g yarn > /dev/null

echo -e "${GREEN}[*] Installing Pterodactyl dependencies...${NC}"
cd "$PTERODACTYL_PATH"
yarn install > /dev/null

echo -e "${GREEN}[*] Installing additional dependencies...${NC}"
apt install -y zip unzip git curl wget > /dev/null

echo -e "${GREEN}[*] Downloading latest Blueprint release...${NC}"
DOWNLOAD_URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | cut -d '"' -f 4)
wget "$DOWNLOAD_URL" -O "$PTERODACTYL_PATH/release.zip" > /dev/null

echo -e "${GREEN}[*] Extracting Blueprint...${NC}"
cd "$PTERODACTYL_PATH"
unzip -o release.zip > /dev/null
rm release.zip

echo -e "${GREEN}[*] Running Blueprint installer...${NC}"
chmod +x blueprint.sh
./blueprint.sh

# Custom completion message
echo -e "${PURPLE}"
echo "╔══════════════════════════════════════════════╗"
echo "║          Installation Complete!              ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Thank you for using my custom installer     ║"
echo "║                                              ║"
echo "║  Need help? Contact me on Discord:           ║"
echo "║  unbelievablegirl.exe                        ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YELLOW}To get started with Blueprint:"
echo "- Run 'blueprint -help' to see available commands"
echo "- Check the documentation for extension development"
echo "- Explore available extensions"
echo -e "${NC}"
