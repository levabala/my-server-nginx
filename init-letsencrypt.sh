#!/bin/bash

# Initialize Let's Encrypt certificates for nginx with docker-compose
set -e  # Exit immediately if a command exits with a non-zero status

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

domains=(dubna-hirudo.ru define.click www.define.click)
rsa_key_size=4096
data_path="./certbot"
email="admin@dubna-hirudo.ru" # Adding a valid email is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

if [ -d "$data_path" ]; then
  echo "Existing data found for $domains. Replacing existing certificate..."
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  if ! curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"; then
    echo "Error: Failed to download options-ssl-nginx.conf" >&2
    exit 1
  fi
  if ! curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"; then
    echo "Error: Failed to download ssl-dhparams.pem" >&2
    exit 1
  fi
  echo
fi

echo "### Creating dummy certificate for $domains ..."
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
if ! docker-compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot; then
  echo "Error: Failed to create dummy certificate" >&2
  exit 1
fi
echo

echo "### Starting nginx ..."
if ! docker-compose up --force-recreate -d nginx; then
  echo "Error: Failed to start nginx" >&2
  exit 1
fi
echo

echo "### Deleting dummy certificate for $domains ..."
if ! docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot; then
  echo "Error: Failed to delete dummy certificate" >&2
  exit 1
fi
echo

echo "### Requesting Let's Encrypt certificate for $domains ..."
# Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

if ! docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot; then
  echo "Error: Failed to obtain Let's Encrypt certificate" >&2
  exit 1
fi
echo

echo "### Reloading nginx ..."
if ! docker-compose exec nginx nginx -s reload; then
  echo "Error: Failed to reload nginx" >&2
  exit 1
fi