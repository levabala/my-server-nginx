# My Server Nginx

A deployable nginx server setup with SSL/TLS support via Let's Encrypt, extracted from the dubna-hirudo project.

## Features

- **SSL/TLS termination** with Let's Encrypt certificates
- **HTTP to HTTPS redirect** for all traffic
- **Static file serving** for web applications
- **Security headers** and gzip compression
- **Automated certificate renewal** via certbot
- **Blue-green deployment** strategy in CI/CD
- **Health checking** and automatic rollback on deployment failure

## Deployment

### Prerequisites

- Docker and docker-compose installed on target server
- GitHub secrets configured for SSH access:
  - `YA_CLOUD_PROD_HOST`
  - `YA_CLOUD_PROD_USERNAME` 
  - `YA_CLOUD_PROD_KEY`
  - `YA_CLOUD_PROD_PORT`

### Automated Deployment

1. Create a git tag with semantic versioning:
   ```bash
   git tag v1.0.0
   git push origin main --tags
   ```

2. The GitHub Actions workflow will automatically:
   - Build the Docker image
   - Transfer it to the production server
   - Deploy with SSL certificate management
   - Perform health checks
   - Rollback on failure

### Manual Deployment

1. Copy your static files to `dist/` directory
2. Copy additional files to `other/` directory (optional)
3. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your domain and email
   ```
4. Initialize SSL certificates (first time only):
   ```bash
   ./init-letsencrypt.sh
   ```
5. Start services:
   ```bash
   docker-compose up -d
   ```

## Configuration

### Environment Variables

- `DOMAIN`: Your domain name (e.g., example.com)
- `EMAIL`: Email for Let's Encrypt notifications
- `DOCKER_IMAGE`: Docker image tag to deploy

### Nginx Configuration

The nginx configuration includes:
- SSL/TLS settings with modern cipher suites
- Security headers (HSTS, XSS protection, etc.)
- Gzip compression
- Custom error pages
- ACME challenge handling for certificate renewal

## Directory Structure

```
my-server-nginx/
├── nginx/
│   └── nginx.conf          # Nginx server configuration
├── .github/
│   └── workflows/
│       └── release.yml     # GitHub Actions deployment workflow
├── docker-compose.yml      # Docker services definition
├── Dockerfile             # Docker image build instructions
├── init-letsencrypt.sh    # SSL certificate initialization script
├── .env.example           # Environment variables template
├── .dockerignore          # Docker build ignore rules
├── .gitignore            # Git ignore rules
└── README.md             # This file
```

## Usage

This setup is designed to serve static files from the `dist/` directory. To use it:

1. Build your static website/application
2. Copy the built files to `dist/`
3. Deploy using the methods described above

The nginx server will serve your static files with proper SSL termination and security headers.
