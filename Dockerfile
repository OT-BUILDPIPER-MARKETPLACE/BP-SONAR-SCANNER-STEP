FROM sonarsource/sonar-scanner-cli

RUN apk add --no-cache --upgrade bash
RUN apk add jq
COPY BP-BASE-SHELL-STEPS/functions.sh .

ENV SONAR_HOST_URL ""
ENV SONAR_TOKEN ""

ENV ACTIVITY_SUB_TASK_CODE BP-SONAR-SCANNER
ENV SLEEP_DURATION 5s
ENV VALIDATION_FAILURE_ACTION WARNING
COPY build.sh .
ENTRYPOINT [ "./build.sh" ]
