FROM debian:bookworm-slim

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

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-17-jdk \
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
        libssl-dev \
        build-essential \
        make \
        gcc \
        findutils \
        xz-utils \
        gettext-base \
        tar && \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Install JDK 21
# ------------------------------------------------------------

ENV JAVA_HOME_21=/opt/jdk/jdk-21

RUN mkdir -p /opt/jdk/jdk-21 && \
    curl -fsSL \
      "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse" \
      -o /tmp/jdk21.tar.gz && \
    tar -xzf /tmp/jdk21.tar.gz \
      --strip-components=1 \
      -C /opt/jdk/jdk-21 && \
    rm -f /tmp/jdk21.tar.gz && \
    chown -R buildpiper:buildpiper /opt/jdk

# ------------------------------------------------------------
# SonarScanner
# ------------------------------------------------------------

ENV SONAR_SCANNER_VERSION=8.0.1.6346

RUN set -eux; \
    curl -fsSL \
      -o /tmp/sonar.zip \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip"; \
    unzip -q /tmp/sonar.zip -d /opt; \
    echo "=== Extracted SonarScanner directories ==="; \
    find /opt -maxdepth 2 -type d -name '*sonar-scanner*' -print; \
    SCANNER_DIR=$(find /opt -maxdepth 1 -type d -name "sonar-scanner-*" | head -n 1); \
    echo "SCANNER_DIR=${SCANNER_DIR}"; \
    test -n "${SCANNER_DIR}"; \
    test -f "${SCANNER_DIR}/bin/sonar-scanner"; \
    rm -rf /opt/sonar-scanner; \
    mv "${SCANNER_DIR}" /opt/sonar-scanner; \
    chmod +x /opt/sonar-scanner/bin/sonar-scanner; \
    ln -sf /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner; \
    rm -f /tmp/sonar.zip
# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------

RUN python3 -m venv /home/buildpiper/venv && \
    /home/buildpiper/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /home/buildpiper/venv/bin/pip install --no-cache-dir tabulate cryptography

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

ENV JAVA_HOME=/opt/jdk/jdk-21
ENV PATH="/opt/jdk/jdk-21/bin:/home/buildpiper/venv/bin:/usr/local/bin:/opt/sonar-scanner/bin:/usr/bin:/bin"

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

# Copy scripts
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data /opt/buildpiper/data
COPY --chown=buildpiper:buildpiper build.sh /opt/buildpiper/
COPY --chown=buildpiper:buildpiper getDynamicVars.sh /opt/buildpiper/

RUN chmod +x /opt/buildpiper/*.sh && \
    chown -R buildpiper:buildpiper /opt/buildpiper

USER buildpiper
WORKDIR /opt/buildpiper/

# Verify Java 21
RUN echo "Java version:" && \
    java -version && \
    echo "JAVA_HOME=${JAVA_HOME}"

# Verify SonarScanner
RUN echo "SonarScanner version:" && \
    sonar-scanner --version || \
    (echo "[ERROR] sonar-scanner failed to execute!" && exit 1)

ENTRYPOINT ["/opt/buildpiper/build.sh"]