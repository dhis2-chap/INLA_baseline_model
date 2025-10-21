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

# Install tini for proper signal handling
RUN apt-get update && \
    apt-get install -y --no-install-recommends tini && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy Python venv and application files
COPY --from=builder /app/.venv /app/.venv
COPY train.R predict.R lib.R inla_baseline_service.py /app/

WORKDIR /app

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
CMD ["sh", "-c", "effective_cpus() { base=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1); if read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null; then if [ $quota != max ]; then echo $(( (quota + period - 1) / period )); return; fi; fi; echo $base; }; CPUS=$(effective_cpus); WORKERS=${WORKERS:-$(( CPUS * 2 + 1 ))}; FORWARDED_ALLOW_IPS=${FORWARDED_ALLOW_IPS:-*}; GUNICORN_CONF=$(python -c 'import servicekit, os; print(os.path.join(os.path.dirname(servicekit.__file__), \"gunicorn.conf.py\"))'); exec gunicorn -c \"${GUNICORN_CONF}\" -k uvicorn.workers.UvicornWorker inla_baseline_service:app --bind 0.0.0.0:${PORT} --workers ${WORKERS} --timeout ${TIMEOUT} --graceful-timeout ${GRACEFUL_TIMEOUT} --keep-alive ${KEEPALIVE} --forwarded-allow-ips=${FORWARDED_ALLOW_IPS} --max-requests ${MAX_REQUESTS} --max-requests-jitter ${MAX_REQUESTS_JITTER} --worker-tmp-dir /dev/shm"]
