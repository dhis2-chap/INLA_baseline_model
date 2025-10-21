# Docker Deployment

## Quick Start

```bash
# Build and start
docker compose up --build

# Run in background
docker compose up -d --build

# View logs
docker compose logs -f

# Stop
docker compose down
```

Service available at `http://localhost:8000`

## Manual Docker Commands

```bash
# Build
docker build -t inla-baseline-service .

# Run
docker run -p 8000:8000 inla-baseline-service

# Run in background
docker run -d -p 8000:8000 --name inla-baseline inla-baseline-service

# Stop
docker stop inla-baseline && docker rm inla-baseline
```

## Test the Service

```bash
curl http://localhost:8000/health
curl http://localhost:8000/api/v1/info

# Or open in browser
http://localhost:8000/docs
```

## Base Image

Uses `ghcr.io/dhis2-chap/docker_r_inla` which includes:
- R with INLA library
- All required R packages (yaml, jsonlite, dplyr, dlnm, sf, spdep)

The Dockerfile adds Python 3, chapkit (from `fix-ml-config-additions` branch), and FastAPI.

## Troubleshooting

**Check logs:**
```bash
docker logs inla-baseline
```

**Port already in use:**
```bash
docker run -p 8080:8000 inla-baseline-service
```

**Rebuild from scratch:**
```bash
docker compose build --no-cache
```