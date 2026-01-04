#!/bin/sh
set -e

# Function to create self-signed certificate if it doesn't exist
create_dummy_cert() {
    domain=$1
    cert_path="/etc/letsencrypt/live/$domain"
    
    if [ ! -f "$cert_path/fullchain.pem" ] || [ ! -f "$cert_path/privkey.pem" ]; then
        echo "Creating dummy certificate for $domain..."
        mkdir -p "$cert_path"
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout "$cert_path/privkey.pem" \
            -out "$cert_path/fullchain.pem" \
            -subj "/CN=$domain"
        echo "Dummy certificate created for $domain"
    else
        echo "Certificate already exists for $domain"
    fi
}

# Create dummy certs for all domains if they don't exist
create_dummy_cert "dubna-hirudo.ru"
create_dummy_cert "define.click"

# Start nginx
exec nginx -g 'daemon off;'
