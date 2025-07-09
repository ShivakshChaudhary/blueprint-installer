#!/bin/bash

set -euo pipefail

######################################################################################
#                                                                                    #
# Enhanced Pterodactyl Installer Script                                              #
#                                                                                    #
# Copyright (C) 2018 - 2025, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
# Modifications (C) 2023, Your Name                                                  #
#                                                                                    #
# This program is free software: you can redistribute it and/or modify               #
# it under the terms of the GNU General Public License as published by               #
# the Free Software Foundation, either version 3 of the License, or                  #
# (at your option) any later version.                                                #
#                                                                                    #
# This script is not associated with the official Pterodactyl Project.               #
######################################################################################

# Global configuration
export GITHUB_SOURCE="v1.1.1"
export SCRIPT_RELEASE="v1.1.1"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"
export LOG_PATH="/var/log/pterodactyl-installer.log"
export TMP_DIR="/tmp/pterodactyl-installer"
export CONFIG_DIR="/etc/pterodactyl-installer"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_PATH")"
    echo -e "\n\n* Pterodactyl Installer $(date) \n\n" >> "$LOG_PATH"
}

# Error handling
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo -e "[ERROR] $(date) - $1" >> "$LOG_PATH"
    exit 1
}

# Warning message
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    echo -e "[WARNING] $(date) - $1" >> "$LOG_PATH"
}

# Info message
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo -e "[INFO] $(date) - $1" >> "$LOG_PATH"
}

# Success message
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo -e "[SUCCESS] $(date) - $1" >> "$LOG_PATH"
}

# Check for required commands
check_dependencies() {
    local dependencies=("curl" "awk" "grep" "sed")
    local missing=()
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}. Please install them before proceeding."
    fi
}

# Download library file
download_lib() {
    mkdir -p "$TMP_DIR"
    curl -sSL -o "$TMP_DIR/lib.sh" "$GITHUB_BASE_URL/master/lib/lib.sh" || error "Failed to download library file"
    # shellcheck source=/dev/null
    source "$TMP_DIR/lib.sh"
}

# Cleanup temporary files
cleanup() {
    rm -rf "$TMP_DIR"
    info "Cleanup completed"
}

# Main execution function
execute() {
    local component=$1
    local next_component=$2

    [[ "$component" == *"canary"* ]] && {
        export GITHUB_SOURCE="master"
        export SCRIPT_RELEASE="canary"
        warning "Using canary version - this may be unstable!"
    }

    update_lib_source
    
    info "Starting installation of $component"
    run_ui "${component//_canary/}" |& tee -a "$LOG_PATH" || {
        error "Installation of $component failed"
    }

    if [[ -n "$next_component" ]]; then
        echo -e -n "* Installation of $component completed. Proceed to $next_component installation? (y/N): "
        read -r -n 1 CONFIRM
        echo
        if [[ "$CONFIRM" =~ [Yy] ]]; then
            execute "$next_component"
        else
            warning "Installation of $next_component aborted by user."
        fi
    fi
}

# Display welcome message
welcome() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
  ____  _                      _            _   _ 
 |  _ \| |__   ___   ___ _ __ | |_ ___  ___| |_| |
 | |_) | '_ \ / _ \ / _ \ '_ \| __/ _ \/ __| __| |
 |  __/| | | | (_) |  __/ | | | ||  __/\__ \ |_|_|
 |_|   |_| |_|\___/ \___|_| |_|\__\___||___/\__(_)
EOF
    echo -e "${NC}"
    echo -e "Enhanced Pterodactyl Installer ${SCRIPT_RELEASE}"
    echo -e "Copyright (C) 2018 - 2025, Vilhelm Prytz"
    echo -e "Modifications (C) 2023, Your Name"
    echo
}

# Main menu
main_menu() {
    local done=false
    while [ "$done" == false ]; do
        options=(
            "Install the panel"
            "Install Wings"
            "Install both panel and Wings on the same machine"
            "Uninstall panel or wings"
            "Install panel (canary version)"
            "Install Wings (canary version)"
            "Install both panel and Wings (canary versions)"
            "Uninstall panel or wings (canary version)"
        )

        actions=(
            "panel"
            "wings"
            "panel;wings"
            "uninstall"
            "panel_canary"
            "wings_canary"
            "panel_canary;wings_canary"
            "uninstall_canary"
        )

        echo -e "\n${BLUE}What would you like to do?${NC}\n"
        
        for i in "${!options[@]}"; do
            printf "${YELLOW}[%d]${NC} %s\n" "$i" "${options[$i]}"
        done

        echo -ne "\n* Input 0-$((${#actions[@]} - 1)): "
        read -r action

        [ -z "$action" ] && error "Input is required" && continue

        if [[ "$action" =~ ^[0-9]+$ ]] && [ "$action" -ge 0 ] && [ "$action" -lt ${#actions[@]} ]; then
            done=true
            IFS=";" read -r i1 i2 <<<"${actions[$action]}"
            execute "$i1" "$i2"
        else
            error "Invalid option selected"
        fi
    done
}

# Main function
main() {
    init_logging
    check_dependencies
    welcome
    download_lib
    main_menu
    cleanup
}

# Trap signals for cleanup
trap cleanup EXIT
trap 'error "Script interrupted by user"; exit 1' INT TERM

# Entry point
main