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

# Set working directory
WORKDIR /home/buildpiper

# Copy your custom scripts
COPY build.sh getDynamicVars.sh ./
COPY BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY BP-BASE-SHELL-STEPS/data /opt/buildpiper/data/
RUN  mkdir -p /bp/execution_dir && chown -R 1001:1001 /bp

# Make scripts executable
RUN chmod +x build.sh getDynamicVars.sh

RUN useradd -ms /bin/bash buildpiper && chown -R buildpiper:buildpiper /home/buildpiper

USER buildpiper

ENTRYPOINT ["./build.sh"]
