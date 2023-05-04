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

sonar-scanner -Dsonar.login=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR -Dsonar.java.binaries=$CODEBASE_DIR

if [ $? -eq 0 ]
then
  logInfoMessage "Congratulations sonar scan succeeded!!!"
  generateOutput mvn_execute true "Congratulations sonar scan succeeded!!!"
elif [ $VALIDATION_FAILURE_ACTION == "FAILURE" ]
  then
    logErrorMessage "Please check sonar scan failed!!!"
    generateOutput mvn_execute false "Please check sonar scan failed!!!!!"
    echo "build unsucessfull"
    exit 1
   else
    logWarningMessage "Please check sonar scan failed!!!"
    generateOutput mvn_execute true "Please check sonar scan failed!!!!!"
fi