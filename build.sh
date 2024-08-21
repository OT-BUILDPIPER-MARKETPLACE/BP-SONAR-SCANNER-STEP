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
logInfoMessage "Starting SonarQube scan. Workspace: [$WORKSPACE], Codebase Directory: [$CODEBASE_DIR]"

# Define the code directory
code="$WORKSPACE/$CODEBASE_DIR"
logInfoMessage "Arguments received: [$@]"

# Change to the code directory
cd "$code" || { logErrorMessage "Failed to change directory to $code"; exit 1; }

# Run the SonarQube scanner
logInfoMessage "Running SonarQube scanner..."
sonar-scanner -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR -Dsonar.java.binaries=. $SONAR_ARGS
TASK_STATUS=$?

# Check if sonar-scanner executed successfully
if [ $TASK_STATUS -ne 0 ]; then
    logErrorMessage "SonarQube scanner failed with status code $TASK_STATUS"
    exit 1
fi

logInfoMessage "SonarQube scan completed. Sleeping for $SLEEP_DURATION seconds to allow data processing..."
sleep $SLEEP_DURATION       

# Fetch SonarQube results
logInfoMessage "Fetching SonarQube metrics..."
response=$(curl -s -w "%{http_code}" -u $SONAR_TOKEN: -X GET "${SONAR_URL}api/measures/component?component=$CODEBASE_DIR&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" -o response.json)

# Extract the HTTP status code
http_code=$(echo "$response" | tail -n1)
logInfoMessage "HTTP status code from SonarQube API: $http_code"

# Check if the request was successful (HTTP 200)
if [ "$http_code" -eq 200 ]; then
    # If successful, parse the JSON
    json=$(jq '.' response.json)
    if [ $? -ne 0 ]; then
        logErrorMessage "Failed to parse JSON response. The JSON might be malformed."
        exit 1
    fi
    logInfoMessage "Successfully fetched and parsed SonarQube metrics."
else
    # Handle different types of errors
    case "$http_code" in
        401)
            logErrorMessage "Unauthorized. The SONAR_TOKEN might not have sufficient permissions to access the metrics."
            ;;
        403)
            logErrorMessage "Forbidden. Access to the requested resource is forbidden. Check if the SONAR_TOKEN has the required permissions."
            ;;
        404)
            logErrorMessage "Not Found. The requested component or resource could not be found. Check the SONAR_URL and CODEBASE_DIR."
            ;;
        500)
            logErrorMessage "Internal Server Error. Something went wrong on the SonarQube server."
            ;;
        *)
            logErrorMessage "Failed to fetch SonarQube metrics. HTTP Status Code: $http_code."
            ;;
    esac

    # Output the response for further investigation
    echo "[DEBUG] Response received:"
    cat response.json
    exit 1
fi

# Ensure the reports directory exists
mkdir -p reports

# Process and save the SonarQube summary
logInfoMessage "Processing SonarQube metrics into CSV format..."
echo "$json" | jq -r '.component.measures | map({metric: .metric, value: .value}) | (map(.metric) | @csv), (map(.value) | @csv)' | sed 's/"//g' > reports/sonar_summary.csv

# Check if the sonar_summary.csv file was created successfully
if [ ! -f reports/sonar_summary.csv ]; then
    logErrorMessage "Failed to create reports/sonar_summary.csv"
    echo "Build unsuccessful"
    exit 1
fi

# List the generated report file
logInfoMessage "Generated report file: reports/sonar_summary.csv"
ls reports/sonar_summary.csv

# Log the execution of the summary presentation
logInfoMessage "Presenting SonarQube scan summary..."

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

# Send the MI data and capture the status
sendMIData sonar.mi ${MI_SERVER_ADDRESS}
MI_STATUS=$?

# Check the status of MI data sending
if [ $MI_STATUS -ne 0 ]; then
    logErrorMessage "Failed to send MI data. MI Server response code: $MI_STATUS"
fi

# Conditional logging based on the success or failure of both the scan and the report sending
if [ $TASK_STATUS -eq 0 ] && [ $MI_STATUS -eq 0 ]; then
    logInfoMessage "Congratulations, Sonar scan succeeded and the report was successfully sent to the MI server!!!"
    generateOutput sonar_scan true "Congratulations, Sonar scan succeeded and the report was successfully sent to the MI server!!!"
elif [ $TASK_STATUS -eq 0 ]; then
    logWarningMessage "Sonar scan succeeded, but the report was not sent to the MI server. Please check the MI server status."
    generateOutput sonar_scan true "Sonar scan succeeded, but the report was not sent to the MI server. Please check the MI server status."
else
    if [ "$VALIDATION_FAILURE_ACTION" == "FAILURE" ]; then
        logErrorMessage "Sonar scan failed. Please check the logs for details."
        generateOutput sonar_scan false "Sonar scan failed. Please check the logs for details."
        echo "Build unsuccessful"
        exit 1
    else
        logWarningMessage "Sonar scan failed. Please check the logs for details."
        generateOutput sonar_scan true "Sonar scan failed. Please check the logs for details."
    fi
fi

# Save the task status
saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}
