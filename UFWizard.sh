#!/bin/bash

# Create necessary directories
CONFIG_DIR="/usr/local/bin/ufwizard/config"
mkdir -p "$CONFIG_DIR"

# URLs for configuration files
WHITELIST_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/allowed_ports.txt"
OUT_IP_FILE_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/blocked_out_ips.txt"

# Local paths
WHITELISTED_IPS_FILE="$CONFIG_DIR/whitelisted_ips.txt"
PREVIOUS_HASHES_FILE="$CONFIG_DIR/previous_hashes.txt"

# Function to install UFW if not installed
install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "UFW is not installed. Installing..."
        sudo apt update
        sudo apt install -y ufw
    else
        echo "UFW is already installed."
    fi
}

# Function to fetch and update UFW rules from GitHub
fetch_and_update_rules() {
    local whitelist_file=$(mktemp)
    local out_ip_file=$(mktemp)

    download_file "$WHITELIST_URL" "$whitelist_file"
    download_file "$OUT_IP_FILE_URL" "$out_ip_file"

    local new_whitelist_hash=$(generate_file_hash "$whitelist_file")
    local new_out_ip_hash=$(generate_file_hash "$out_ip_file")

    if [[ -f "$PREVIOUS_HASHES_FILE" ]]; then
        read -r previous_whitelist_hash previous_out_ip_hash < "$PREVIOUS_HASHES_FILE"
    else
        previous_whitelist_hash=""
        previous_out_ip_hash=""
        touch "$PREVIOUS_HASHES_FILE"
    fi

    if [[ "$new_whitelist_hash" != "$previous_whitelist_hash" || "$new_out_ip_hash" != "$previous_out_ip_hash" ]]; then
        echo "Configuration files have changed. Updating UFW rules..."
        sudo ufw --force reset

        echo "Allowing new ports..."
        while IFS= read -r port; do
            sudo ufw allow "$port"
            echo "Allowed port $port"
        done < "$whitelist_file"

        echo "Blocking outgoing traffic to new IPs..."
        while IFS= read -r out_ip; do
            if [[ "$out_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                sudo ufw deny out to "$out_ip"
                echo "Blocked outgoing traffic to $out_ip"
            else
                echo "Invalid IP format: $out_ip"
            fi
        done < "$out_ip_file"

        echo "Allowing whitelisted IPs..."
        if [[ -f "$WHITELISTED_IPS_FILE" ]]; then
            while IFS= read -r ip; do
                sudo ufw allow to "$ip"
                echo "Allowed incoming to $ip"
            done < "$WHITELISTED_IPS_FILE"
        else
            echo "No whitelisted IPs found."
        fi

        echo "Enabling UFW..."
        sudo ufw --force enable
        echo "$new_whitelist_hash $new_out_ip_hash" > "$PREVIOUS_HASHES_FILE"
    else
        echo "No changes detected in configuration files."
    fi

    rm "$whitelist_file" "$out_ip_file"
}

# Function to download a file from a URL
download_file() {
    local url="$1"
    local output_file="$2"
    curl -s -o "$output_file" "$url"
}

# Function to generate a hash of a file
generate_file_hash() {
    sha256sum "$1" | awk '{print $1}'
}

# Function to whitelist an IP address
whitelist_ip() {
    read -p "Enter the IP address to whitelist: " ip_address
    echo "$ip_address" >> "$WHITELISTED_IPS_FILE"
    echo "Whitelisted IP $ip_address."
}

# Function to display the current UFW rules
show_rules() {
    echo "Current UFW Rules:"
    sudo ufw status
    read -p "Press Enter to continue..."
}

# Function to delete a specific UFW rule by its number
delete_rule() {
    read -p "Enter the rule number to delete: " rule_number
    if sudo ufw delete "$rule_number"; then
        echo "Deleted rule number $rule_number."
    else
        echo "Failed to delete rule number $rule_number."
    fi
}

# Function to remove all UFW rules
remove_all_rules() {
    echo "Removing all UFW rules..."
    sudo ufw --force reset
    echo "All UFW rules have been removed."
}

# Function to set up a cron job for automatic updates
setup_cron() {
    (crontab -l 2>/dev/null; echo "0 */3 * * * bash /usr/local/bin/ufwizard/ufwizard.sh 1") | crontab -
}

# Function to remove the cron job
remove_cron() {
    crontab -l | grep -v 'bash /usr/local/bin/ufwizard/ufwizard.sh 1' | crontab -
}

# Main menu
main_menu() {
    while true; do
        echo "UFWizard"
        echo "=============================="
        echo "1. Update UFW Rules from GitHub"
        echo "2. Show current rules"
        echo "3. Whitelist an IP address"
        echo "4. Delete a specific rule"
        echo "5. Remove all UFW rules"
        echo "6. Set up cron job for automatic updates"
        echo "7. Remove cron job for automatic updates"
        echo "8. Exit"
        echo "=============================="
        read -p "Choose an option: " option

        case $option in
            1) fetch_and_update_rules ;;
            2) show_rules ;;
            3) whitelist_ip ;;
            4) delete_rule ;;
            5) remove_all_rules ;;
            6) setup_cron ;;
            7) remove_cron ;;
            8) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

# Main function to handle script parameters
main() {
    install_ufw

    case "$1" in
        1) fetch_and_update_rules ;;  # Updated parameter from 3 to 1
        *) main_menu ;;
    esac
}

# Run the main function with parameters
main "$@"
