FROM debian:bullseye-slim

# Create non-root user
RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -d /home/buildpiper -m -s /bin/bash buildpiper && \
    mkdir -p /opt/buildpiper /opt/sonar-scanner && \
    chown -R buildpiper:buildpiper /home/buildpiper /opt/buildpiper /opt/sonar-scanner

RUN mkdir -p \
    /src/reports \
    /bp/data \
    /bp/execution_dir \
    /opt/buildpiper/shell-functions \
    /opt/buildpiper/data \
    /bp/workspace \
    /usr/local/bin \
    /var/lib/apt/lists \
    /opt/python_versions \
    /opt/jdk \
    /opt/maven \
    /app/venv && \
    chown -R buildpiper:buildpiper /src /bp /opt /usr /tmp /app

RUN echo "Asia/Kolkata" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        unzip \
        bash \
        git \
        jq \
        python3 \
        python3-venv \
        python3-pip \
        ca-certificates \
        openssl \
        libffi-dev \
        build-essential \
        gettext-base && \
    rm -rf /var/lib/apt/lists/*

# Install Sonar Scanner manually
# ENV SONAR_SCANNER_VERSION=5.0.1.3006
# RUN curl -fsSL -o /tmp/sonar.zip \
#     "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" && \
#     unzip /tmp/sonar.zip -d /opt/sonar-scanner && \
#     mv /opt/sonar-scanner/sonar-scanner-* /opt/sonar-scanner/bin && \
#     ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
#     rm -rf /tmp/sonar.zip

ENV SONAR_SCANNER_VERSION=5.0.1.3006
RUN curl -fsSL -o /tmp/sonar.zip \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" && \
    unzip /tmp/sonar.zip -d /opt && \
    mv /opt/sonar-scanner-* /opt/sonar-scanner && \
    SONAR_PATH=$(find /opt/sonar-scanner -type f -name sonar-scanner | head -n 1) && \
    ln -s "$SONAR_PATH" /usr/local/bin/sonar-scanner && \
    chmod +x "$SONAR_PATH" && \
    rm -rf /tmp/sonar.zip

# Create and prepare Python virtual environment
RUN python3 -m venv /home/buildpiper/venv && \
    /home/buildpiper/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /home/buildpiper/venv/bin/pip install --no-cache-dir tabulate cryptography

# Copy scripts
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data /opt/buildpiper/data
COPY --chown=buildpiper:buildpiper build.sh /opt/buildpiper/
COPY --chown=buildpiper:buildpiper getDynamicVars.sh /opt/buildpiper/
RUN chmod +x /opt/buildpiper/*.sh && \
    chown -R buildpiper:buildpiper /opt/buildpiper

# Set environment
# ENV PATH="/home/buildpiper/venv/bin:/opt/sonar-scanner/bin:$PATH"
ENV PATH="/home/buildpiper/venv/bin:/usr/local/bin:/opt/sonar-scanner/bin:/usr/bin:/bin:$PATH"

ENV APPLICATION_NAME=""
ENV ORGANIZATION=""
ENV SOURCE_KEY=""
ENV REPORT_FILE_PATH="null"
ENV JAVA_BINARIES=""
ENV SONAR_TOKEN=""
ENV SONAR_URL=""
ENV SONAR_ARGS=""
ENV MI_SERVER_ADDRESS=""
ENV ACTIVITY_SUB_TASK_CODE="BP-SONAR-SCANNER"
ENV SLEEP_DURATION="30s"
ENV VALIDATION_FAILURE_ACTION="WARNING"
ENV NODE_OPTIONS="--max-old-space-size=8192"

USER buildpiper
WORKDIR /opt/buildpiper/

# Verify sonar installation during build
RUN sonar-scanner --version || (echo "[ERROR] sonar-scanner failed to execute!" && exit 1)

ENTRYPOINT ["/opt/buildpiper/build.sh"]
