FROM ubuntu:22.04

ENV SONAR_SCANNER_VERSION=5.0.1.3006

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

RUN curl -Lo sonar-scanner.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip && \
    unzip sonar-scanner.zip -d /opt && \
    mv /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux /opt/sonar-scanner && \
    rm sonar-scanner.zip

ENV PATH="/opt/sonar-scanner/bin:$PATH"

RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -d /home/buildpiper -s /bin/bash -m buildpiper && \
    chown -R buildpiper:buildpiper /home/buildpiper

WORKDIR /home/buildpiper


COPY --chown=buildpiper:buildpiper build.sh getDynamicVars.sh ./
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data /opt/buildpiper/data/


RUN mkdir -p /bp/execution_dir && chown -R buildpiper:buildpiper /bp


RUN chmod +x build.sh getDynamicVars.sh


USER buildpiper

ENTRYPOINT ["./build.sh"]
