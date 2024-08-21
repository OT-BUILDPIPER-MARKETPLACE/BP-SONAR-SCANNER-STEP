#!/bin/bash

# Source necessary functions
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/mi-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh

# Initialize task status
TASK_STATUS=0
SLEEP_DURATION=${SLEEP_DURATION:-30}
# Log information about the task
logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"

# Define the code directory
code="$WORKSPACE/$CODEBASE_DIR"
logInfoMessage "I've received the following arguments: [$@]"

# Change to the code directory
cd $code

# Run the SonarQube scanner
sonar-scanner -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR -Dsonar.java.binaries=. $SONAR_ARGS
TASK_STATUS=$?

# Require sleep of 30 sec after publishing the data to fetch back the report
sleep $SLEEP_DURATION       

# Fetch SonarQube results
response=$(curl -s -w "%{http_code}" -u $SONAR_TOKEN: -X GET "${SONAR_URL}api/measures/component?component=$CODEBASE_DIR&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" -o response.json)

# Extract the HTTP status code
http_code=$(echo "$response" | tail -n1)

# Initialize flag for metrics fetch success
METRICS_FETCH_SUCCESS=1

# Check if the request was successful (HTTP 200)
if [ "$http_code" -eq 200 ]; then
    # If successful, parse the JSON
    json=$(jq '.' response.json)
    echo "[INFO] Successfully fetched SonarQube metrics."
else
    # If not successful, handle different types of errors
    case "$http_code" in
        401)
            echo "[ERROR] Unauthorized. The SONAR_TOKEN might not have sufficient permissions to access the metrics."
            ;;
        403)
            echo "[ERROR] Forbidden. Access to the requested resource is forbidden. Check if the SONAR_TOKEN has the required permissions."
            ;;
        404)
            echo "[ERROR] Not Found. The requested component or resource could not be found. Check the SONAR_URL and CODEBASE_DIR."
            ;;
        500)
            echo "[ERROR] Internal Server Error. Something went wrong on the SonarQube server."
            ;;
        *)
            echo "[ERROR] Failed to fetch SonarQube metrics. HTTP Status Code: $http_code."
            ;;
    esac

    # Output the response for further investigation
    echo "[DEBUG] Response received:"
    cat response.json

    # Set a flag to indicate the failure in fetching metrics
    METRICS_FETCH_SUCCESS=0
fi

# Ensure the reports directory exists
mkdir -p reports

# Process and save the SonarQube summary if metrics fetching was successful
if [ $METRICS_FETCH_SUCCESS -eq 1 ]; then
    echo $json | jq -r '.component.measures | map({metric: .metric, value: .value}) | (map(.metric) | @csv), (map(.value) | @csv)' | sed 's/"//g' > reports/sonar_summary.csv

    # Check if the sonar_summary.csv file was created successfully
    if [ ! -f reports/sonar_summary.csv ]; then
        logErrorMessage "Failed to create reports/sonar_summary.csv"
        echo "Build unsuccessful"
        MI_SEND_STATUS=1
    else
        # List the generated report file
        ls reports/sonar_summary.csv

        # Log the execution of the summary presentation
        logInfoMessage "Executing command to present the accumulated summary for Sonar Scanning in the Application Code"

        # Display the summary
        cat reports/sonar_summary.csv

        # Encode the report file content
        export base64EncodedResponse=$(encodeFileContent reports/sonar_summary.csv)

        # Set environment variables for MI data
        export application=$APPLICATION_NAME
        export environment=$(getProjectEnv)
        export service=$(getServiceName)
        export organization=$ORGANIZATION
        export source_key=$SOURCE_KEY
        export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

        # Check the MI send status
        if [ $? -eq 0 ]; then
            MI_SEND_STATUS=0
        else
            MI_SEND_STATUS=1
        fi
    fi
else
    MI_SEND_STATUS=1
fi

# Conditional logging based on the success or failure of the scan and MI report sending
if [ $TASK_STATUS -eq 0 ] && [ $MI_SEND_STATUS -eq 0 ]; then
    logInfoMessage "Congratulations, Sonar scan succeeded and the report was successfully sent to the MI server!!!"
    generateOutput sonar_scan true "Congratulations, Sonar scan succeeded and the report was successfully sent to the MI server!!!"
elif [ $TASK_STATUS -eq 0 ] && [ $MI_SEND_STATUS -eq 1 ]; then
    logWarningMessage "Sonar scan succeeded, but the report was not sent to the MI server."
    generateOutput sonar_scan false "Sonar scan succeeded, but the report was not sent to the MI server."
else
    logWarningMessage "Sonar scan failed. Please check the logs for details."
    generateOutput sonar_scan false "Sonar scan failed. Please check the logs for details."
fi

# Save the task status
saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}
