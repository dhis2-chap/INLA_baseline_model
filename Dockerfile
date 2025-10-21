# Builder stage - install Python dependencies with uv
FROM ghcr.io/astral-sh/uv:0.9-python3.13-bookworm-slim AS builder

WORKDIR /workspace

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

# Runtime stage - R INLA base image
FROM ghcr.io/dhis2-chap/docker_r_inla@sha256:adfc916416f7cd56d6d0368cfdf22d5a24844cafe626259ca9dc48a695142feb

# OCI labels for container metadata
LABEL org.opencontainers.image.title="INLA Baseline Model"
LABEL org.opencontainers.image.description="INLA Bayesian hierarchical model with chapkit integration"
LABEL org.opencontainers.image.vendor="DHIS2 CHAP"
LABEL org.opencontainers.image.source="https://github.com/dhis2-chap/INLA_baseline_model"

# Copy Python virtual environment from builder
COPY --from=builder /workspace/.venv /opt/venv

# Set up environment to use the venv
ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONFAULTHANDLER=1

# Set working directory
WORKDIR /app

# Copy model files
COPY train.R predict.R lib.R inla_baseline_service.py ./

# Expose port for FastAPI
EXPOSE 8000

# Health check to verify the API is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health').read()" || exit 1

# Command to run the service
CMD ["fastapi", "run", "inla_baseline_service.py", "--host", "0.0.0.0", "--port", "8000"]
