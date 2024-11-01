FROM sonarsource/sonar-scanner-cli

USER root

# Install bash, curl, and other dependencies
RUN apk add --no-cache --upgrade bash \
    gettext \
    git \
    libintl \
    curl \
    jq \
    python3 \
    py3-pip \
    gcc \
    libffi-dev \
    musl-dev \
    openssl-dev \
    python3-dev \
    make

# Create a Python virtual environment
RUN python3 -m venv /root/venv

# Activate the virtual environment and install the cryptography library
RUN . /root/venv/bin/activate && pip install --no-cache-dir cryptography

ADD BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
ADD BP-BASE-SHELL-STEPS/data /opt/buildpiper/data

ENV APPLICATION_NAME ""
ENV ORGANIZATION ""
ENV SOURCE_KEY ""
ENV REPORT_FILE_PATH null
ENV JAVA_BINARIES ""

ENV SONAR_TOKEN ""
ENV SONAR_URL ""
ENV SONAR_ARGS ""
ENV MI_SERVER_ADDRESS ""
ENV ACTIVITY_SUB_TASK_CODE BP-SONAR-SCANNER
ENV SLEEP_DURATION 30s
ENV VALIDATION_FAILURE_ACTION WARNING
ENV NODE_OPTIONS --max-old-space-size=8192

# Use the virtual environment's Python for the container
ENV PATH="/root/venv/bin:$PATH"

COPY build.sh .
COPY getDynamicVars.sh .

ENTRYPOINT [ "./build.sh" ]