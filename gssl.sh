#!/bin/bash

colors=( "\033[1;31m" "\033[1;92m" "\033[1;36m" "\033[1;33m" "\033[0m" )
red=${colors[0]} green=${colors[1]} cyan=${colors[2]} yellow=${colors[3]} reset=${colors[4]}

print() { echo -e "${cyan}$1${reset}"; }
error() { echo -e "${red}✗ $1${reset}"; }

trap 'echo -e "\n${red}Script interrupted!${reset}"; exit 1' SIGINT

validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $1"
        return 1
    fi
    return 0
}

install_acme() {
    if ! command -v socat &> /dev/null; then
        print "Installing socat..."
        local pkg_manager
        if command -v apt-get &> /dev/null; then
            pkg_manager="apt-get"
            $pkg_manager update -y > /dev/null 2>&1
            $pkg_manager install -y socat > /dev/null 2>&1 || { error "Failed to install socat"; exit 1; }
        elif command -v dnf &> /dev/null; then
            pkg_manager="dnf"
            $pkg_manager install -y socat > /dev/null 2>&1 || { error "Failed to install socat"; exit 1; }
        elif command -v yum &> /dev/null; then
            pkg_manager="yum"
            $pkg_manager install -y socat > /dev/null 2>&1 || { error "Failed to install socat"; exit 1; }
        else
            error "No supported package manager found. Please install socat manually."
            exit 1
        fi
        print "done"
    fi

    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        print "Installing acme.sh..."
        curl https://get.acme.sh | sh -s email="$email" > /dev/null 2>&1 || { error "Failed to install acme.sh"; exit 1; }
        source ~/.bashrc
        print "done"
    fi
}

get_certificate() {
    local domains=("$@")
    local domain_args=""
    local main_domain="${domains[0]}"

    for domain in "${domains[@]}"; do
        domain=$(echo "$domain" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        domain_args+=" -d $domain"
    done

    print "Getting SSL certificate..."
    ~/.acme.sh/acme.sh --issue --standalone $domain_args --accountemail "$email" > /dev/null 2>&1 || { error "Failed to obtain SSL certificate"; return 1; }
    print "done"
    return 0
}

renew_certificate() {
    local main_domain="$1"
    print "Renewing SSL certificate..."
    ~/.acme.sh/acme.sh --renew -d "$main_domain" > /dev/null 2>&1 || { error "Failed to renew SSL certificate"; return 1; }
    print "done"
    return 0
}

delete_certificate() {
    local main_domain="$1"
    print "Deleting SSL certificate..."
    ~/.acme.sh/acme.sh --remove -d "$main_domain" > /dev/null 2>&1 || { error "Failed to delete SSL certificate"; return 1; }
    print "done"
    return 0
}

install_marzban_certificate() {
    local main_domain="$1"
    local cert_dir="/var/lib/marzban/certs"
    local cert_file="$cert_dir/$main_domain.cer"
    local key_file="$cert_dir/$main_domain.cer.key"

    print "Installing certificate..."
    mkdir -p "$cert_dir" || { error "Failed to create certificate directory"; return 1; }
    ~/.acme.sh/acme.sh --install-cert -d "$main_domain" \
        --fullchain-file "$cert_file" \
        --key-file "$key_file" > /dev/null 2>&1 || { error "Failed to install certificate"; return 1; }
    print "done"
    print "Certificate: $cert_file"
    print "Private key: $key_file"
}

install_marzneshin_certificate() {
    local main_domain="$1"
    local cert_dir="/var/lib/marzneshin/certs"
    local cert_file="$cert_dir/cert.crt"
    local key_file="$cert_dir/private.key"

    print "Installing certificate..."
    mkdir -p "$cert_dir" || { error "Failed to create certificate directory"; return 1; }
    ~/.acme.sh/acme.sh --install-cert -d "$main_domain" \
        --fullchain-file "$cert_file" \
        --key-file "$key_file" > /dev/null 2>&1 || { error "Failed to install certificate"; return 1; }
    print "done"
    print "Certificate: $cert_file"
    print "Private key: $key_file"
}

show_menu() {
    clear
    echo "=== GSSL SSL Management Panel ==="
    echo "1) Get SSL Certificate"
    echo "2) Renew SSL Certificate"
    echo "3) Delete SSL Certificate"
    echo "4) Exit"
    echo "================================"
    read -p "Select an option (1-4): " choice
    echo
    case "$choice" in
        1) action="get" ;;
        2) action="renew" ;;
        3) action="delete" ;;
        4) print "Exiting..."; exit 0 ;;
        *) error "Invalid option. Please select 1-4."; sleep 2; show_menu ;;
    esac
}

select_panel() {
    echo "Which panel are you using?"
    echo "1) Marzban"
    echo "2) Marzneshin"
    read -p "Enter 1 or 2: " panel_choice
    if [[ "$panel_choice" != "1" && "$panel_choice" != "2" ]]; then
        error "Invalid panel choice."
        exit 1
    fi
}

get_inputs() {
    if [ "$action" != "delete" ]; then
        read -p "Enter your email address: " email
        if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            error "Invalid email format."
            exit 1
        fi
    fi

    read -p "Enter domain(s) (space-separated for multiple domains, e.g., example.com sub.example.com): " -a domains
    if [ ${#domains[@]} -eq 0 ]; then
        error "At least one domain is required."
        exit 1
    fi
    for domain in "${domains[@]}"; do
        validate_domain "$domain" || exit 1
    done

    if [ "$action" == "renew" ] || [ "$action" == "delete" ]; then
        if [ ${#domains[@]} -ne 1 ]; then
            error "Renew and delete commands support only one domain."
            exit 1
        fi
    fi
}

main() {
    [ "$EUID" -eq 0 ] || { error "This script must be run as root."; exit 1; }

    show_menu
    select_panel
    get_inputs
    install_acme

    local main_domain="${domains[0]}"
    case "$action" in
        get)
            if get_certificate "${domains[@]}"; then
                if [ "$panel_choice" == "1" ]; then
                    install_marzban_certificate "$main_domain"
                elif [ "$panel_choice" == "2" ]; then
                    install_marzneshin_certificate "$main_domain"
                fi
            fi
            ;;
        renew)
            if renew_certificate "$main_domain"; then
                if [ "$panel_choice" == "1" ]; then
                    install_marzban_certificate "$main_domain"
                elif [ "$panel_choice" == "2" ]; then
                    install_marzneshin_certificate "$main_domain"
                fi
            fi
            ;;
        delete)
            if [ "$panel_choice" == "1" ]; then
                delete_certificate "$main_domain"
            elif [ "$panel_choice" == "2" ]; then
                delete_certificate "$main_domain"
            fi
            ;;
    esac
}

main
