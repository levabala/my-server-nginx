#!/bin/bash

# Initialize Let's Encrypt certificates for nginx with docker-compose
# This script uses standalone mode to obtain certificates without nginx running,
# then starts nginx with the real certificates.

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

# Stop any running containers first
echo "### Stopping any running containers..."
docker-compose down 2>/dev/null || true

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

# Clean up any existing certificate data
echo "### Cleaning up existing certificate data..."
rm -rf "$data_path/conf/live" "$data_path/conf/archive" "$data_path/conf/renewal" 2>/dev/null || true
mkdir -p "$data_path/conf"

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
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

echo "### Requesting Let's Encrypt certificates using standalone mode..."
# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

all_certs_obtained=true

for domain_group in "${domain_groups[@]}"; do
  primary_domain=$(echo $domain_group | cut -d' ' -f1)
  
  # Build domain args for this group
  domain_args=""
  for domain in $domain_group; do
    domain_args="$domain_args -d $domain"
  done
  
  echo "Requesting certificate for: $domain_group"
  
  # Use standalone mode - certbot runs its own temporary web server on port 80
  # This doesn't require nginx to be running
  set +e
  docker run --rm \
    -p 80:80 \
    -v "$(pwd)/$data_path/conf:/etc/letsencrypt" \
    -v "$(pwd)/$data_path/www:/var/www/certbot" \
    -v "$(pwd)/$data_path/logs:/var/log/letsencrypt" \
    certbot/certbot certonly --standalone \
      $staging_arg \
      $email_arg \
      $domain_args \
      --cert-name $primary_domain \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --non-interactive 2>&1 | grep -v "ddtrace\|dd\.service=\|datadog"
  certbot_exit=${PIPESTATUS[0]}
  set -e
  
  if [ $certbot_exit -eq 0 ]; then
    echo "Successfully obtained real certificate for $domain_group"
  else
    echo "Error: Failed to obtain Let's Encrypt certificate for $domain_group (exit code: $certbot_exit)" >&2
    all_certs_obtained=false
  fi
done
echo

if [ "$all_certs_obtained" = false ]; then
  echo "Error: Not all certificates were obtained. Please check the logs above." >&2
  exit 1
fi

echo "### Starting services..."
docker-compose up -d

echo "### Verifying certificates..."
sleep 2
docker-compose logs nginx | tail -10

echo
echo "### Certificate initialization complete!"
echo "Certificates are saved in $data_path/conf/live/"
ls -la "$data_path/conf/live/" 2>/dev/null || echo "Warning: Could not list certificates"
