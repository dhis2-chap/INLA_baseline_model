# INLA Baseline Model Dockerfile
FROM ghcr.io/astral-sh/uv:0.9-python3.13-bookworm-slim AS builder

WORKDIR /app

# Install git for fetching dependencies from git repositories
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# UV configuration for better build performance
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Copy project files
COPY pyproject.toml uv.lock ./

# Install dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# Cleanup Python cache files
RUN find .venv -type d -name '__pycache__' -prune -exec rm -rf {} + && \
    find .venv -type f -name '*.py[co]' -delete || true

# ---- runtime ----
FROM ghcr.io/dhis2-chap/docker_r_inla@sha256:adfc916416f7cd56d6d0368cfdf22d5a24844cafe626259ca9dc48a695142feb AS runtime

# OCI labels for container metadata
LABEL org.opencontainers.image.title="INLA Baseline Model"
LABEL org.opencontainers.image.description="INLA Bayesian hierarchical model with chapkit integration"
LABEL org.opencontainers.image.vendor="DHIS2 CHAP"
LABEL org.opencontainers.image.source="https://github.com/dhis2-chap/INLA_baseline_model"

# Install tini and curl for uv installation
RUN apt-get update && \
    apt-get install -y --no-install-recommends tini curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy uv from builder stage
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv

# Copy Python venv and application files
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/pyproject.toml /app/uv.lock /app/
COPY train.R predict.R lib.R inla_baseline_service.py /app/

WORKDIR /app

# Create python symlink that venv scripts expect (remove existing one first)
RUN rm -f /app/.venv/bin/python && ln -s /usr/bin/python3 /app/.venv/bin/python

# Set up environment to use the venv
ENV VIRTUAL_ENV=/app/.venv
ENV PATH=/app/.venv/bin:${PATH}
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONFAULTHANDLER=1

# Server configuration
ENV PORT=8000
ENV TIMEOUT=60
ENV GRACEFUL_TIMEOUT=30
ENV KEEPALIVE=5
ENV FORWARDED_ALLOW_IPS="*"

# Worker configuration
ENV MAX_REQUESTS=1000
ENV MAX_REQUESTS_JITTER=200

# Logging configuration
ENV LOG_FORMAT=json
ENV LOG_LEVEL=INFO

EXPOSE 8000

# Health check to verify the API is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/health').read()" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/.venv/bin/gunicorn", "-k", "uvicorn.workers.UvicornWorker", "inla_baseline_service:app", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "60", "--graceful-timeout", "30", "--keep-alive", "5", "--max-requests", "1000", "--max-requests-jitter", "200", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "--error-logfile", "-"]
