#!/bin/bash

# Source necessary functions
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/mi-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh
source /opt/buildpiper/shell-functions/getDataFile.sh
source getDynamicVars.sh

# Initialize task status
TASK_STATUS=0
WORKSPACE="/bp/workspace"
SLEEP_DURATION=${SLEEP_DURATION:-30}
JAVA_BINARIES=${JAVA_BINARIES:-.}  # Default to '.' if not set
# Set environment variables for MI data handling for V3 Step
environment="${PROJECT_ENV_NAME:-$(getProjectEnv)}"
service="${COMPONENT_NAME:-$(getServiceName)}"

# Log information about the task
logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"

# Suggest customizing JAVA_BINARIES
if [ "$JAVA_BINARIES" == "target/classes" ]; then
    logInfoMessage "[SUGGESTION] The JAVA_BINARIES variable is currently set to the default value of 'target/classes'."
    logInfoMessage "[SUGGESTION] If your compiled Java classes are located in a different directory, you can set the JAVA_BINARIES environment variable to that directory's path."
    logInfoMessage "[SUGGESTION] Example: export JAVA_BINARIES=target/classes"
else
    logInfoMessage "Using JAVA_BINARIES set to: $JAVA_BINARIES"
fi

# Define the code directory
code="$WORKSPACE/$CODEBASE_DIR"
logInfoMessage "I've received the following arguments: [$@]"

# Change to the code directory
cd $code

# Main logic to check conditions and call fetch_service_details
if [ -n "$SOURCE_VARIABLE_REPO" ]; then
    # Check if TELEGRAM_TOKEN, TELEGRAM_CHAT_ID, and DNS_URL are provided
    if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_URL" ]; then
        echo "SONAR_TOKEN and SONAR_URLare provided. Skipping fetching details from SOURCE_VARIABLE_REPO."
    else
        echo "Fetching details from $SOURCE_VARIABLE_REPO as SONAR_TOKEN and SONAR_URL are not provided."
        fetch_service_details
    fi
else
    echo "-------------------------------------------SOURCE_VARIABLE_REPO-------------------------------------------"
    logInfoMessage "SOURCE_VARIABLE_REPO is not set. Skipping fetch operation as the source repository is undefined."
    echo "-------------------------------------------SOURCE_VARIABLE_REPO-------------------------------------------"
fi

# Check required environment variables
required_vars=("SONAR_TOKEN" "SONAR_URL" "APPLICATION_NAME" "ORGANIZATION" "MI_SERVER_ADDRESS")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=($var)
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "[ERROR] The following required environment variables are missing: ${missing_vars[*]}"
    exit 1
fi

logInfoMessage "Sonar Url: $SONAR_URL"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Run the SonarQube scanner
sonar-scanner -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR -Dsonar.java.binaries=$JAVA_BINARIES -Dsonar.branch.name=$CURRENT_BRANCH $SONAR_ARGS
TASK_STATUS=$?

# Set default value for SONAR_GATE_CHECK if not already set
SONAR_GATE_CHECK=${SONAR_GATE_CHECK:-false}

# Set local sleep duration specifically for this part of the script
localSleepDuration=${SLEEP_DURATION:-300}

# Require sleep of 300 sec after publishing the data to fetch back the report
if [ "$SONAR_GATE_CHECK" == "true" ]; then
    logInfoMessage "Waiting for Quality Gate Check for "$localSleepDuration" Seconds"
    sleep "$localSleepDuration"
    
    # Get SonarQube Quality Check Status
    statusResponse=$(curl -s -u "$SONAR_TOKEN": "${SONAR_URL}/api/qualitygates/project_status?projectKey=$CODEBASE_DIR")
    
    # Check if curl was successful
    if [ $? -ne 0 ]; then
        logInfoMessage "Failed to fetch SonarQube quality gate status!"
        exit 1
    fi

    gateStatus=$(echo "$statusResponse" | jq -r .projectStatus.status)

    # Check if the status is "ERROR" (i.e., quality gate failed)
    if [ "$gateStatus" == "ERROR" ]; then
        logInfoMessage "SonarQube quality gate failed!"
        # exit 1
    else
        logInfoMessage "SonarQube quality gate passed."
        # exit 0
    fi
else
    logInfoMessage "Skipping Quality Gates Test"
fi

TASK_STATUS=$?

# Require sleep of 30 sec after publishing the data to fetch back the report
SLEEP_DURATION=${SLEEP_DURATION:-30}
sleep $SLEEP_DURATION    

# Fetch SonarQube results
response=$(curl -s -w "%{http_code}" -u $SONAR_TOKEN: -X GET "${SONAR_URL}/api/measures/component?component=$CODEBASE_DIR&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" -o response.json)

# Extract the HTTP status code
http_code=$(echo "$response" | tail -n1)

# Initialize flag for metrics fetch success
METRICS_FETCH_SUCCESS=1

# Check if the request was successful (HTTP 200)
if [ "$http_code" -eq 200 ]; then
    # If successful, parse the JSON
    json=$(jq '.' response.json)
    logInfoMessage "Successfully fetched SonarQube metrics."
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
            echo "[ERROR] Not Found. The requested component or resource could not be found. Check the ${SONAR_URL} and ${CODEBASE_DIR}."
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

        # # Display the summary
        # cat reports/sonar_summary.csv
        # Display the original CSV 
        # NOTE: Using python3 print_table.py custom script to print the tabular data.
        logInfoMessage "Displaying Original Report: reports/sonar_summary.csv"
        echo "================================================================================"
        python3 /opt/buildpiper/shell-functions/print_table.py reports/sonar_summary.csv
        echo "================================================================================"

        logInfoMessage "Updating reports in /bp/execution_dir/${GLOBAL_TASK_ID}......."
        cp -rf reports/* /bp/execution_dir/${GLOBAL_TASK_ID}/

        # Encode the report file content
        export base64EncodedResponse=$(encodeFileContent reports/sonar_summary.csv)

        # Define potential SOURCE_KEY values to fall back on
        # source_keys=("sonarqube_blocker_violations" "sonarqube_bugs" "sonarqube_security_rating" "sonarqube_code_smells" "sonarqube_major_violations")

logInfoMessage "-------------------------- Initiating data push to the Maturity Dashboard for 'sonarqube_blocker_violations' metrics --------------------------"

        # Set environment variables for MI data
        export application=$APPLICATION_NAME
        export environment=$environment
        export service=$service
        export organization=$ORGANIZATION
        export source_key=sonarqube_blocker_violations
        export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

# Send the MI data and check the result
if sendMIData sonar.mi ${MI_SERVER_ADDRESS}; then
    logInfoMessage "-------------------------- Successfully completed the data push for 'sonarqube_blocker_violations' metrics --------------------------"
else
    logErrorMessage "-------------------------- Failed to push data for 'sonarqube_blocker_violations' metrics. Please check the MI server address or the generated JSON file. --------------------------"
fi

logInfoMessage "-------------------------- Initiating data push to the Maturity Dashboard for 'sonarqube_bugs' metrics --------------------------"

        # Set environment variables for MI data
        export application=$APPLICATION_NAME
        export environment=$environment
        export service=$service
        export organization=$ORGANIZATION
        export source_key=sonarqube_bugs
        export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

# Send the MI data and check the result
if sendMIData sonar.mi ${MI_SERVER_ADDRESS}; then
    logInfoMessage "-------------------------- Successfully completed the data push for 'sonarqube_bugs' metrics --------------------------"
else
    logErrorMessage "-------------------------- Failed to push data for 'sonarqube_bugs' metrics. Please check the MI server address or the generated JSON file. --------------------------"
fi

logInfoMessage "-------------------------- Initiating data push to the Maturity Dashboard for 'sonarqube_security_rating' metrics --------------------------"

        # Set environment variables for MI data
        export application=$APPLICATION_NAME
        export environment=$environment
        export service=$service
        export organization=$ORGANIZATION
        export source_key=sonarqube_security_rating
        export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

# Send the MI data and check the result
if sendMIData sonar.mi ${MI_SERVER_ADDRESS}; then
    logInfoMessage "-------------------------- Successfully completed the data push for 'sonarqube_security_rating' metrics --------------------------"
else
    logErrorMessage "-------------------------- Failed to push data for 'sonarqube_security_rating' metrics. Please check the MI server address or the generated JSON file. --------------------------"
fi

logInfoMessage "-------------------------- Initiating data push to the Maturity Dashboard for 'sonarqube_code_smells' metrics --------------------------"

        # Set environment variables for MI data
        export application=$APPLICATION_NAME
        export environment=$environment
        export service=$service
        export organization=$ORGANIZATION
        export source_key=sonarqube_code_smells
        export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

# Send the MI data and check the result
if sendMIData sonar.mi ${MI_SERVER_ADDRESS}; then
    logInfoMessage "-------------------------- Successfully completed the data push for 'sonarqube_code_smells' metrics --------------------------"
else
    logErrorMessage "-------------------------- Failed to push data for 'sonarqube_code_smells' metrics. Please check the MI server address or the generated JSON file. --------------------------"
fi

logInfoMessage "-------------------------- Initiating data push to the Maturity Dashboard for 'sonarqube_major_violations' metrics --------------------------"

        # Set environment variables for MI data
            export application=$APPLICATION_NAME
            export environment=$environment
            export service=$service
            export organization=$ORGANIZATION
            export source_key=sonarqube_major_violations
            export report_file_path=$REPORT_FILE_PATH

        # Generate MI data JSON
        generateMIDataJson /opt/buildpiper/data/mi.template sonar.mi

        # Log the JSON to be sent
        logInfoMessage "Sonar Scanning JSON to be sent to MI server"
        cat sonar.mi

        # Send the MI data
        sendMIData sonar.mi ${MI_SERVER_ADDRESS}

# Send the MI data and check the result
if sendMIData sonar.mi ${MI_SERVER_ADDRESS}; then
    logInfoMessage "-------------------------- Successfully completed the data push for 'sonarqube_major_violations' metrics --------------------------"
else
    logErrorMessage "-------------------------- Failed to push data for 'sonarqube_major_violations' metrics. Please check the MI server address or the generated JSON file. --------------------------"
fi

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
