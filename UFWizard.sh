#!/bin/bash

SCRIPT_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/UFWizard.sh"
LOCAL_SCRIPT_PATH="/usr/local/bin/ufwizard/ufwizard.sh"

check_and_save_script() {
    if [[ ! -f "$LOCAL_SCRIPT_PATH" ]]; then
        echo "Script not found at $LOCAL_SCRIPT_PATH. Downloading..."
        curl -s -o "$LOCAL_SCRIPT_PATH" "$SCRIPT_URL"
        chmod +x "$LOCAL_SCRIPT_PATH"
        echo "Script saved to $LOCAL_SCRIPT_PATH."
    else
        echo "Script already exists at $LOCAL_SCRIPT_PATH."
    fi
}

check_and_save_script

CONFIG_DIR="/usr/local/bin/ufwizard/config"
mkdir -p "$CONFIG_DIR"

WHITELIST_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/allowed_ports.txt"
OUT_IP_FILE_URL="https://raw.githubusercontent.com/alefvanoon/UFWizard/main/config/blocked_out_ips.txt"

WHITELISTED_IPS_FILE="$CONFIG_DIR/whitelisted_ips.txt"
PREVIOUS_HASHES_FILE="$CONFIG_DIR/previous_hashes.txt"

install_ufw() {
    if ! command -v ufw &> /dev/null; then
        echo "UFW is not installed. Installing..."
        sudo apt update
        sudo apt install -y ufw
    else
        echo "UFW is already installed."
    fi
}

fetch_and_update_rules() {
    local force_update="$1"
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

    if [[ "$force_update" == "true" || "$new_whitelist_hash" != "$previous_whitelist_hash" || "$new_out_ip_hash" != "$previous_out_ip_hash" ]]; then
        echo "Updating UFW rules..."
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

download_file() {
    local url="$1"
    local output_file="$2"
    curl -s -o "$output_file" "$url"
}

generate_file_hash() {
    sha256sum "$1" | awk '{print $1}'
}

whitelist_ip() {
    read -p "Enter the IP address to whitelist: " ip_address
    echo "$ip_address" >> "$WHITELISTED_IPS_FILE"
    echo "Whitelisted IP $ip_address."
}

show_rules() {
    echo "Current UFW Rules:"
    sudo ufw status
    read -p "Press Enter to continue..."
}

delete_rule() {
    read -p "Enter the rule number to delete: " rule_number
    if sudo ufw delete "$rule_number"; then
        echo "Deleted rule number $rule_number."
    else
        echo "Failed to delete rule number $rule_number."
    fi
    read -p "Press Enter to continue..."
}

remove_all_rules() {
    echo "Removing all UFW rules..."
    sudo ufw --force reset
    echo "All UFW rules have been removed."
    read -p "Press Enter to continue..."
}

setup_cron() {
    (crontab -l 2>/dev/null; echo "0 */3 * * * bash $LOCAL_SCRIPT_PATH 1") | crontab -
    echo "Cron job for automatic updates has been set up."
    read -p "Press Enter to continue..."
}

remove_cron() {
    crontab -l | grep -v "bash $LOCAL_SCRIPT_PATH 1" | crontab -
    echo "Cron job for automatic updates has been removed."
    read -p "Press Enter to continue..."
}

force_update() {
    fetch_and_update_rules "true"
}

main_menu() {
    while true; do
        echo "UFWizard"
        echo "=============================="
        echo "1. Update UFW Rules from GitHub"
        echo "2. Force Update UFW Rules from GitHub"
        echo "3. Show current rules"
        echo "4. Whitelist an IP address"
        echo "5. Delete a specific rule"
        echo "6. Remove all UFW rules"
        echo "7. Set up cron job for automatic updates"
        echo "8. Remove cron job for automatic updates"
        echo "9. Exit"
        echo "=============================="
        read -p "Choose an option: " option

        case $option in
            1) fetch_and_update_rules "false" ;;
            2) force_update ;;
            3) show_rules ;;
            4) whitelist_ip ;;
            5) delete_rule ;;
            6) remove_all_rules ;;
            7) setup_cron ;;
            8) remove_cron ;;
            9) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

main() {
    install_ufw

    case "$1" in
        1) fetch_and_update_rules "false" ;;
        *) main_menu ;;
    esac
}

main "$@"
