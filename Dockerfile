FROM ubuntu:22.04

# Set environment variables
ENV SONAR_SCANNER_VERSION=5.0.1.3006

# Install required system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    make \
    gcc \
    libffi-dev \
    libssl-dev \
    findutils \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install sonar-scanner
RUN curl -Lo sonar-scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip && \
    unzip sonar-scanner.zip -d /opt && \
    mv /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux /opt/sonar-scanner && \
    rm sonar-scanner.zip

# Add sonar-scanner to PATH
ENV PATH="/opt/sonar-scanner/bin:$PATH"

# Create non-root user with fixed UID/GID = 65522
RUN groupadd -g 65522 buildpiper && \
    useradd -m -u 65522 -g 65522 -s /bin/bash buildpiper

# Set working directory
WORKDIR /home/buildpiper

# Copy your custom scripts
COPY --chown=65522:65522 build.sh getDynamicVars.sh ./
COPY --chown=65522:65522 BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY --chown=65522:65522 BP-BASE-SHELL-STEPS/data /opt/buildpiper/data/

# Create execution directory with correct ownership
RUN mkdir -p /bp/execution_dir && chown -R 65522:65522 /bp

# Make scripts executable
RUN chmod +x build.sh getDynamicVars.sh

# Switch to non-root user
USER buildpiper

ENTRYPOINT ["./build.sh"]
