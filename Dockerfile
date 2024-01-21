FROM sonarsource/sonar-scanner-cli

RUN apk add --no-cache --upgrade bash
RUN apk add jq

ADD BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
ADD BP-BASE-SHELL-STEPS/data /opt/buildpiper/data

ENV SONAR_TOKEN ""
ENV SONAR_URL ""
ENV SONAR_ARGS ""
ENV ACTIVITY_SUB_TASK_CODE BP-SONAR-SCANNER
ENV SLEEP_DURATION 5s
ENV VALIDATION_FAILURE_ACTION WARNING

COPY build.sh .
ENTRYPOINT [ "./build.sh" ]
