FROM sonarsource/sonar-scanner-cli

RUN apk add --no-cache --upgrade bash
RUN apk add jq

COPY BP-BASE-SHELL-STEPS/functions.sh .
COPY sonar-scanner.properties /opt/sonar-scanner/conf/sonar-scanner.properties 
ENV SONAR_ARGS "-Dproject.settings=sonar.properties"
ENV SONAR_TOKEN ""

ENV ACTIVITY_SUB_TASK_CODE BP-SONAR-SCANNER
ENV SLEEP_DURATION 5s
ENV VALIDATION_FAILURE_ACTION WARNING

COPY build.sh .
ENTRYPOINT [ "./build.sh" ]
