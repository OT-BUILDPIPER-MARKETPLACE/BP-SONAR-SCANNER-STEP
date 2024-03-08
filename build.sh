#!/bin/bash

source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"
sleep $SLEEP_DURATION
cd $WORKSPACE
logInfoMessage "I've recieved below arguments [$@]"

sonar-scanner -Dsonar.host.url="$SONAR_URL" -Dsonar.projectKey="$CODEBASE_DIR" -Dsonar.sources="$WORKSPACE/$CODEBASE_DIR" -Dsonar.token="$SONAR_TOKEN"  "$SONAR_ARGS"

if [ $? -eq 0 ]
then
  logInfoMessage "Congratulations sonar scan succeeded!!!"
  generateOutput sonar_execute true "Congratulations sonar scan succeeded!!!"
elif [ $VALIDATION_FAILURE_ACTION == "FAILURE" ]
  then
    logErrorMessage "Please check sonar scan failed!!!"
    generateOutput sonar_execute false "Please check sonar scan failed!!!!!"
    echo "build unsucessfull"
    exit 1
   else
    logWarningMessage "Please check sonar scan failed!!!"
    generateOutput sonar_execute true "Please check sonar scan failed!!!!!"
fi