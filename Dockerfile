# Base image with R and INLA dependencies
FROM ghcr.io/dhis2-chap/docker_r_inla@sha256:adfc916416f7cd56d6d0368cfdf22d5a24844cafe626259ca9dc48a695142feb

# Install Python 3.13 from deadsnakes PPA
RUN apt-get update && apt-get install -y \
    software-properties-common \
    git \
    curl \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y \
    python3.13 \
    python3.13-venv \
    python3.13-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install pip for Python 3.13
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.13

# Create a virtual environment with Python 3.13 and activate it
ENV VIRTUAL_ENV=/opt/venv
RUN python3.13 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip
RUN pip install --upgrade pip

# Install chapkit from the specific GitHub branch
RUN pip install git+https://github.com/winterop-com/chapkit.git@fix-ml-config-additions

# Set working directory
WORKDIR /app

# Copy model files
COPY train.R predict.R lib.R inla_baseline_service.py ./

# Expose port for FastAPI
EXPOSE 8000

# Set environment variable for FastAPI
ENV PYTHONUNBUFFERED=1

# Command to run the service
CMD ["fastapi", "run", "inla_baseline_service.py", "--host", "0.0.0.0", "--port", "8000"]