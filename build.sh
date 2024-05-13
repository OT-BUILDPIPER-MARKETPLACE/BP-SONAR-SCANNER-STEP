#!/bin/bash

source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/mi-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh

TASK_STATUS=0

logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"
sleep $SLEEP_DURATION

code="$WORKSPACE/$CODEBASE_DIR" 
logInfoMessage "I've recieved below arguments [$@]"

cd $code

sonar-scanner -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR -Dsonar.java.binaries=. "$SONAR_ARGS"
TASK_STATUS=$?

json=$(curl -s -u $SONAR_TOKEN: -X GET "${SONAR_URL}api/measures/component?component=$CODEBASE_DIR&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" | jq '.')

echo $json | jq -r '.component.measures | map({metric: .metric, value: .value}) | (map(.metric) | @csv), (map(.value) | @csv)' | sed 's/"//g' > reports/sonar_summary.csv

logInfoMessage "Executing command to present the accumulated summary for Sonar Scanning in the Application Code"

cat reports/sonar_summary.csv
export base64EncodedResponse=`encodeFileContent reports/sonar_summary.csv`

export application=$APPLICATION_NAME
export environment=`getProjectEnv`
export service=`getServiceName`
export organization=$ORGANIZATION
export source_key=$SOURCE_KEY
export report_file_path=$REPORT_FILE_PATH

generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi
logInfoMessage "Sonar Scanning json to be sent to MI server"
cat sonar.mi
sendMIData sonar.mi ${MI_SERVER_ADDRESS}

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}
# if [ $? -eq 0 ]
# then
#   logInfoMessage "Congratulations sonar scan succeeded!!!"
#   generateOutput mvn_execute true "Congratulations sonar scan succeeded!!!"
# elif [ $VALIDATION_FAILURE_ACTION == "FAILURE" ]
#   then
#     logErrorMessage "Please check sonar scan failed!!!"
#     generateOutput mvn_execute false "Please check sonar scan failed!!!!!"
#     echo "build unsucessfull"
#     exit 1
#    else
#     logWarningMessage "Please check sonar scan failed!!!"
#     generateOutput mvn_execute true "Please check sonar scan failed!!!!!"
# fi
