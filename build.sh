#!/bin/bash
source functions.sh

logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"
sleep  $SLEEP_DURATION
cd  $WORKSPACE/${CODEBASE_DIR}
PROJECTKEY=${CODEBASE_DIR}
logInfoMessage "I've recieved below arguments [$@]"

sonar-scanner -Dsonar.projectKey=$PROJECTKEY -Dsonar.sources=$WORKSPACE/${CODEBASE_DIR}


validateSonarScan() {
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
}

validateQualityGate() {
	sleep 30s
QGSTATUS=`curl -s https://bp-sonar-temp.skuad.in/api/qualitygates/project_status?projectKey=$PROJECTKEY | jq '.projectStatus.status' | tr -d '"'`
echo $QGSTATUS
if [ "$QGSTATUS" = "OK" ]
then
echo "Quality Gate has passed"	
exit 0
elif [ "$QGSTATUS" = "ERROR" ]
then
echo "Quality Gate has failed"
exit 1
fi
}

validateSonarScan
validateQualityGate
