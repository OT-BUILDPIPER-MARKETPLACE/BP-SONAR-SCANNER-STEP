FROM sonarsource/sonar-scanner-cli:latest

USER root

RUN yum install -y bash
RUN yum install -y jq gettext

RUN groupadd -g 65522 buildpiper && \
    useradd -m -u 65522 -g buildpiper -s /bin/bash buildpiper

RUN mkdir -p \
    /opt/buildpiper/shell-functions \
    /bp/workspace \
    /bp/data \
    /bp/execution_dir \
    /src/reports \
    /app \
    /tmp && \
    chown -R buildpiper:buildpiper \
        /opt/buildpiper \
        /bp \
        /src \
        /app \
        /tmp \
        /home/buildpiper

USER buildpiper
WORKDIR /home/buildpiper

ENV NVM_DIR=/home/buildpiper/.nvm

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash

COPY --chown=buildpiper:buildpiper build.sh /build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/ \
    /opt/buildpiper/shell-functions/
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/data \
    /opt/buildpiper/data


ENV APPLICATION_NAME=""
ENV ORGANIZATION=""
ENV SOURCE_KEY=""
ENV REPORT_FILE_PATH=""
ENV JAVA_BINARIES=""

ENV SONAR_TOKEN=""
ENV SONAR_URL=""
ENV SONAR_ARGS=""
ENV MI_SERVER_ADDRESS=""
ENV ACTIVITY_SUB_TASK_CODE=SONARQUBE-SCANNER
ENV SLEEP_DURATION=5s
ENV VALIDATION_FAILURE_ACTION=WARNING
ENV NODE_OPTIONS --max-old-space-size=8192

ENTRYPOINT [ "./build.sh" ]
