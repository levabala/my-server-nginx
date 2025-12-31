# AGENTS.md - Agentic Coding Guidelines

This document provides guidance for AI coding agents working in this repository.

## Project Overview

This is an **infrastructure/DevOps project** - an Nginx reverse proxy and static file server
with SSL/TLS support via Let's Encrypt. It serves three domains:

- `dubna-hirudo.ru` - Static file serving
- `define.click` / `www.define.click` - Reverse proxy to backend service on port 3000
- `letswatchsmth.website` / `www.letswatchsmth.website` - Reverse proxy to backend service on port 3124

**Technology Stack**: Nginx (Alpine Docker), Let's Encrypt/Certbot, Docker Compose, GitHub Actions

## Build/Deploy Commands

This is a configuration-only project with no traditional build system (no package.json, no tests).

```bash
docker build -t my-server-nginx:latest .  # Build Docker image
docker-compose up -d                       # Start all services
docker-compose down                        # Stop all services
docker-compose logs nginx                  # View nginx logs
docker-compose exec nginx nginx -s reload  # Reload nginx config
docker-compose exec nginx nginx -t         # Test nginx config syntax

# SSL Certificate Management
./init-letsencrypt.sh                      # Initialize/renew SSL certificates
NO_DUBNA_HIRUDO=1 ./init-letsencrypt.sh    # Skip dubna-hirudo.ru
NO_DEFINE=1 ./init-letsencrypt.sh          # Skip define.click
NO_LETSWATCHSMTH=1 ./init-letsencrypt.sh   # Skip letswatchsmth.website

# Deployment (triggers GitHub Actions)
git tag v1.0.0 && git push origin main --tags
```

## Deployment Process

The GitHub Actions workflow (`.github/workflows/release.yml`) handles deployment automatically when a semantic version tag is pushed. Here's what happens:

### What the Release Workflow Does

1. **Build & Transfer**: Builds Docker image locally and transfers it to the remote server via SCP
2. **Remote Setup**: SSHs into the server and:
   - Installs Docker/docker-compose if not present
   - Creates `~/my-server-nginx` directory
   - Loads the Docker image
   - Downloads `docker-compose.yml` and `init-letsencrypt.sh` from the tagged commit
   - Creates `.env` with the image tag
   - Runs `docker-compose up -d`

### What the Release Workflow Does NOT Do

- **Does NOT run `init-letsencrypt.sh`** - SSL certificates must be obtained manually

### SSL Certificate Setup (Manual Step Required)

**For new domains or first-time deployment**, you must SSH into the server and run:

```bash
cd ~/my-server-nginx
./init-letsencrypt.sh
```

**Subsequent deployments** reuse existing certificates (persisted in `~/my-server-nginx/certbot/`).

### Adding a New Domain - Full Process

1. Update `nginx/nginx.conf` with HTTP and HTTPS server blocks
2. Update `init-letsencrypt.sh` with new domain group
3. Commit, tag, and push: `git tag v1.x.x && git push origin main --tags`
4. Wait for GitHub Actions to complete
5. **SSH into server and run `./init-letsencrypt.sh`** to obtain certificates for the new domain

## Code Style Guidelines

### Nginx Configuration (`nginx/nginx.conf`)

1. **Indentation**: Use 2 spaces for indentation
2. **Server blocks**: Each domain should have separate HTTP (port 80) and HTTPS (port 443) server blocks
3. **HTTP blocks**: Must include ACME challenge location and redirect to HTTPS
4. **SSL configuration**: Apply consistently across all HTTPS server blocks:
   - TLS 1.2 and 1.3 only
   - Strong cipher suites (ECDHE, AES256-GCM)
   - Session caching enabled
5. **Security headers**: Always include on HTTPS servers:
   ```nginx
   add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
   add_header X-Frame-Options DENY always;
   add_header X-Content-Type-Options nosniff always;
   add_header X-XSS-Protection "1; mode=block" always;
   ```
6. **Gzip**: Enable for text-based content types
7. **Comments**: Use `#` for inline comments explaining purpose of blocks

### Shell Scripts

1. **Shebang**: Always start with `#!/bin/bash`
2. **Error handling**: 
   - Use conditional checks rather than `set -e` for graceful failure handling
   - Use `set -e` only in CI/CD scripts where strict error handling is needed
3. **Logging**: Use `echo` statements to provide clear progress output
4. **Command checks**: Verify commands exist before using: `if ! [ -x "$(command -v docker-compose)" ]`
5. **Cleanup patterns**: Use `|| true` for non-critical cleanup operations

### YAML Files (docker-compose.yml, GitHub Actions)

1. **Indentation**: Use 4 spaces for indentation
2. **Service naming**: Use lowercase with hyphens (kebab-case)
3. **Environment variables**: Use `${VAR_NAME}` syntax for substitution
4. **Restart policy**: Use `restart: unless-stopped` for production services
5. **Volumes**: Use relative paths (`./path`) for bind mounts

### Dockerfile

1. Keep minimal - this project uses a 4-line Dockerfile
2. Use Alpine-based images when possible
3. COPY configuration files explicitly
4. EXPOSE all required ports

## Naming Conventions

| Type | Convention | Examples |
|------|------------|----------|
| Docker images | kebab-case | `my-server-nginx` |
| Directories | kebab-case | `dubna-hirudo-dist`, `define-click-dist` |
| Config files | lowercase | `nginx.conf`, `docker-compose.yml` |
| Environment vars | SCREAMING_SNAKE_CASE | `DOCKER_IMAGE`, `NO_DUBNA_HIRUDO` |
| GitHub secrets | SCREAMING_SNAKE_CASE | `HOST`, `SSH_KEY`, `PORT` |
| Shell variables | lowercase_snake_case | `domain_groups`, `primary_domain` |

## Error Handling Patterns

### Shell Scripts
```bash
# Check command existence
if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

# Non-critical operations - continue on failure
docker image prune -f || true

# Critical operations - exit on failure
if ! curl -s https://example.com/file > output; then
  echo "Error: Failed to download file" >&2
  exit 1
fi
```

### GitHub Actions
```yaml
# Strict error handling for deployment
script: |
  set -e
  # commands here will fail fast
```

## Important Notes for Agents

1. **No tests**: This project has no test suite. Validate changes by:
   - Running `docker-compose exec nginx nginx -t` to test nginx config syntax
   - Building the Docker image: `docker build -t my-server-nginx:test .`

2. **Secrets**: Never commit `.env` files or SSL certificates. Check `.gitignore`.

3. **SSL certificates**: The `certbot/` directory is created by `init-letsencrypt.sh` and
   should never be committed.

4. **Adding new domains**: 
   - Add HTTP server block (port 80) with ACME challenge + redirect
   - Add HTTPS server block (port 443) with full SSL config
   - Update `init-letsencrypt.sh` domain_groups array
   - Add volume mount in `docker-compose.yml` if serving static files

5. **Deployment triggers**: Only semantic version tags (`v1.0.0`) trigger deployment.
   Push to branches does not deploy.

6. **Network**: Services communicate via Docker network `my-server-nginx_default`.
   The `define.click` proxy uses hostname `define` to reach the backend service.

## Validation Checklist

Before submitting changes, verify:

- [ ] `docker build -t my-server-nginx:test .` succeeds
- [ ] `docker-compose exec nginx nginx -t` passes (if nginx running)
- [ ] No secrets or certificates are staged for commit
- [ ] New domains have both HTTP (80) and HTTPS (443) server blocks
- [ ] Security headers are present on all HTTPS server blocks


## Requirements

when asked for non-trivial changes - add a final TODO item: "Update AGENTS.md with important changes, if such"
