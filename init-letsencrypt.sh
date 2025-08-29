#!/bin/bash

# Initialize Let's Encrypt certificates for nginx with docker-compose
# Note: We don't use 'set -e' to allow graceful handling of certificate generation failures

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

# Define domain groups - each group gets its own certificate
domain_groups=()

# Add domain groups based on environment variables
if [ -z "$NO_DUBNA_HIRUDO" ]; then
  domain_groups+=("dubna-hirudo.ru")
fi

if [ -z "$NO_DEFINE" ]; then
  domain_groups+=("define.click www.define.click")
fi

# Check if any domain groups are enabled
if [ ${#domain_groups[@]} -eq 0 ]; then
  echo "No domain groups enabled. All domains disabled via environment variables."
  exit 0
fi
rsa_key_size=4096
data_path="./certbot"
email="admin@dubna-hirudo.ru" # Adding a valid email is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

if [ -d "$data_path" ]; then
  echo "Existing data found. Replacing existing certificates..."
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

echo "### Creating dummy certificates ..."
for domain_group in "${domain_groups[@]}"; do
  # Get first domain as primary domain for cert path
  primary_domain=$(echo $domain_group | cut -d' ' -f1)
  path="/etc/letsencrypt/live/$primary_domain"
  mkdir -p "$data_path/conf/live/$primary_domain"
  echo "Creating dummy certificate for $primary_domain..."
  if ! docker-compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
      -keyout '$path/privkey.pem' \
      -out '$path/fullchain.pem' \
      -subj '/CN=localhost'" certbot 2>&1 | grep -v "ddtrace\|dd\.service=certbot\|datadog"; then
    echo "Error: Failed to create dummy certificate for $primary_domain" >&2
    exit 1
  fi
done
echo

echo "### Starting nginx ..."
if ! docker-compose up --force-recreate -d nginx 2>&1 | grep -v "ddtrace\|dd\.service=\|datadog"; then
  echo "Error: Failed to start nginx" >&2
  exit 1
fi
echo

echo "### Requesting Let's Encrypt certificates ..."
# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

for domain_group in "${domain_groups[@]}"; do
  primary_domain=$(echo $domain_group | cut -d' ' -f1)
  
  # Build domain args for this group
  domain_args=""
  for domain in $domain_group; do
    domain_args="$domain_args -d $domain"
  done
  
  echo "Requesting certificate for: $domain_group"
  if docker-compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot 2>&1 | grep -v "ddtrace\|dd\.service=certbot\|datadog"; then
    
    echo "Successfully obtained real certificate for $domain_group"
  else
    echo "Warning: Failed to obtain Let's Encrypt certificate for $domain_group" >&2
    echo "Nginx will continue to serve with dummy certificate for $primary_domain"
  fi
done
echo

echo "### Reloading nginx ..."
if ! docker-compose exec nginx nginx -s reload 2>&1 | grep -v "ddtrace\|dd\.service=\|datadog"; then
  echo "Error: Failed to reload nginx" >&2
  exit 1
fi