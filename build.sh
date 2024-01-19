#!/bin/bash

source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"
sleep $SLEEP_DURATION

code="$WORKSPACE/$CODEBASE_DIR" 
logInfoMessage "I've recieved below arguments [$@]"

cd $code

sonar-scanner -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$PROJECT_KEY -Dsonar.organization=$ORG_NAME -Dsonar.java.binaries=.  

json=$(curl -u $SONAR_TOKEN: -X GET "${SONAR_URL}api/measures/component?component=${PROJECT_KEY}&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" | jq '.')

echo $json | jq -r '.component.measures | map({metric: .metric, value: .value}) | (map(.metric) | @csv), (map(.value) | @csv)' | sed 's/"//g' > reports/sonar_summary.csv

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
