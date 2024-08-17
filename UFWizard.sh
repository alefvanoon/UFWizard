#!/bin/bash

# Create necessary directories
CONFIG_DIR="/usr/local/bin/ufwizard/config"
mkdir -p "$CONFIG_DIR"

# URL of the whitelist ports file
WHITELIST_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/allowed_ports.txt"

# URL of the outgoing IP ranges file
OUT_IP_FILE_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/blocked_out_ips.txt"

# Path to the local whitelisted IPs file
WHITELISTED_IPS_FILE="$CONFIG_DIR/whitelisted_ips.txt"

# Path to store previous hashes
PREVIOUS_HASHES_FILE="$CONFIG_DIR/previous_hashes.txt"

# Function to install UFW if not installed
install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "UFW is not installed. Installing UFW..."
        sudo apt update
        sudo apt install -y ufw
    else
        echo "UFW is already installed."
    fi
}

# Function to download a file from a URL
download_file() {
    local url="$1"
    local output_file="$2"
    curl -s -o "$output_file" "$url"
}

# Function to generate a hash of a file
generate_file_hash() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# Function to update UFW rules from GitHub
update_rules() {
    # Temporary files to store downloaded content
    local whitelist_file=$(mktemp)
    local out_ip_file=$(mktemp)

    # Download the files
    download_file "$WHITELIST_URL" "$whitelist_file"
    download_file "$OUT_IP_FILE_URL" "$out_ip_file"

    # Generate hashes of the downloaded files
    local new_whitelist_hash=$(generate_file_hash "$whitelist_file")
    local new_out_ip_hash=$(generate_file_hash "$out_ip_file")

    # Load previous hashes from a file (if it exists)
    if [[ -f "$PREVIOUS_HASHES_FILE" ]]; then
        read -r previous_whitelist_hash previous_out_ip_hash < "$PREVIOUS_HASHES_FILE"
    else
        previous_whitelist_hash=""
        previous_out_ip_hash=""
        # Create the file to avoid future errors
        touch "$PREVIOUS_HASHES_FILE"
    fi

    # Check if the hashes have changed
    if [[ "$new_whitelist_hash" != "$previous_whitelist_hash" || "$new_out_ip_hash" != "$previous_out_ip_hash" ]]; then
        echo "Configuration files have changed. Updating UFW rules..."

        # Reset UFW to clear all existing rules
        echo "Resetting UFW to clear all existing rules..."
        sudo ufw reset

        # Allow the specified ports from anywhere
        echo "Allowing new ports..."
        while IFS= read -r port; do
            sudo ufw allow "$port"
            echo "Allowed port $port from anywhere"
        done < "$whitelist_file"

        # Block outgoing traffic to the specified IPs
        echo "Blocking outgoing traffic to new IPs..."
        while IFS= read -r out_ip; do
            sudo ufw deny out to "$out_ip"
            echo "Blocked outgoing traffic to $out_ip"
        done < "$out_ip_file"

        # Allow whitelisted IPs
        echo "Allowing whitelisted IPs..."
        if [[ -f "$WHITELISTED_IPS_FILE" ]]; then
            while IFS= read -r ip; do
                sudo ufw allow to "$ip"
                echo "Allowed incoming to $ip"
            done < "$WHITELISTED_IPS_FILE"
        else
            echo "No whitelisted IPs found."
        fi

        # Enable UFW to apply the new rules
        echo "Enabling UFW..."
        sudo ufw enable

        # Store the new hashes for future comparisons
        echo "$new_whitelist_hash $new_out_ip_hash" > "$PREVIOUS_HASHES_FILE"
    else
        echo "No changes detected in configuration files. No update needed."
    fi

    # Clean up temporary files
    rm "$whitelist_file" "$out_ip_file"
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

# Function to set up a cron job for updating the block list and allowing ports
setup_cron() {
    # Add the cron job directly
    (crontab -l 2>/dev/null; echo "0 */3 * * * bash /usr/local/bin/ufwizard/ufwizard.sh 3") | crontab -
}

# Function to remove the cron job
remove_cron() {
    # Remove the specific cron job
    crontab -l | grep -v 'bash /usr/local/bin/ufwizard/ufwizard.sh 3' | crontab -
}

# Main menu
main_menu() {
    while true; do
        echo "UFWizard"
        echo "1. Show current rules"
        echo "2. Delete a rule"
        echo "3. Update rules from GitHub"
        echo "4. Whitelist an IP address"
        echo "5. Set up cron job for automatic updates"
        echo "6. Remove cron job for automatic updates"
        echo "7. Exit"
        read -p "Choose an option: " option

        case $option in
            1) show_rules ;;  # Show rules only when option 1 is selected
            2) delete_rule ;;
            3) update_rules ;;
            4) whitelist_ip ;;
            5) setup_cron ;;
            6) remove_cron ;;
            7) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

# Main function to handle script parameters
main() {
    # Install UFW if not installed
    install_ufw

    case "$1" in
        3)  # Update block list and allow ports
            update_rules
            ;;
        *)
            main_menu
            ;;
    esac
}

# Run the main function with parameters
main "$@"
