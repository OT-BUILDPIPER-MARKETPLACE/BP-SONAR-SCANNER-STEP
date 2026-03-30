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

###############################################
### EVENTS TRACKING
###############################################
EVENTS='{}'

add_event() {
  local key="${1:-}"
  local status="${2:-}"
  local reason="${3:-}"
  local message="${4:-}"

  if [ -z "$key" ] || [ -z "$status" ]; then
    echo "Error: add_event requires at least 'key' and 'status' parameters" >&2
    return 1
  fi

  key="$(echo "$key" | tr '_' ' ' | tr '-' ' ' | tr '[:upper:]' '[:lower:]')"

  EVENTS=$(jq \
    --arg k "$key" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg message "$message" \
    '. + {($k): {status: $status, reason: $reason, message: $message}}' \
    <<< "$EVENTS") || {
    echo "Error: Failed to add event to EVENTS JSON" >&2
    return 1
  }
}

###############################################
### OUTPUT FILE
###############################################
SONAR_OUTPUT_FILE="${SONAR_OUTPUT_FILE:-sonar_scanning_output.json}"

# Initialize task status
TASK_STATUS=0
WORKSPACE="/bp/workspace"
SLEEP_DURATION=${SLEEP_DURATION:-30}

sonar-scanner --version

# Set environment variables
environment="${PROJECT_ENV_NAME:-$(getProjectEnv)}"
service="${COMPONENT_NAME:-$(getServiceName)}"

###############################################
### CREATE EXECUTION DIRECTORY
###############################################
if [ -n "${GLOBAL_TASK_ID:-}" ]; then
    EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"
    mkdir -p "${EXEC_DIR}"
    add_event "create execution dir" "Successful" "Directory created" "Created ${EXEC_DIR}"
else
    logErrorMessage "GLOBAL_TASK_ID not set; cannot proceed"
    add_event "create execution dir" "Failed" "GLOBAL_TASK_ID missing" "Cannot create execution directory"
    exit 1
fi

# Log information about the task
logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"

# Suggest customizing JAVA_BINARIES
if [ "$JAVA_BINARIES" == "target/classes" ]; then
    logInfoMessage "[SUGGESTION] The JAVA_BINARIES variable is currently set to the default value of 'target/classes'."
    logInfoMessage "[SUGGESTION] If your compiled Java classes are located in a different directory, you can set the JAVA_BINARIES environment variable to that directory's path."
else
    logInfoMessage "Using JAVA_BINARIES set to: $JAVA_BINARIES"
fi

# Define the code directory
code="$WORKSPACE/$CODEBASE_DIR"
logInfoMessage "I've received the following arguments: [$@]"

# Change to the code directory
cd "$code"
add_event "change directory" "Successful" "Directory changed" "Changed to ${code}"

###############################################
### FETCH DYNAMIC VARS IF NEEDED
###############################################
if [ -n "$SOURCE_VARIABLE_REPO" ]; then
    if [ -n "$SONAR_TOKEN" ] && [ -n "$SONAR_URL" ]; then
        echo "SONAR_TOKEN and SONAR_URL are provided. Skipping fetching details from SOURCE_VARIABLE_REPO."
        add_event "fetch dynamic vars" "Successful" "Variables already set" "SONAR credentials provided directly"
    else
        echo "Fetching details from $SOURCE_VARIABLE_REPO as SONAR_TOKEN and SONAR_URL are not provided."
        fetch_service_details
        add_event "fetch dynamic vars" "Successful" "Variables fetched" "Fetched from ${SOURCE_VARIABLE_REPO}"
    fi
else
    logInfoMessage "SOURCE_VARIABLE_REPO is not set. Skipping fetch operation."
    add_event "fetch dynamic vars" "Successful" "Not required" "SOURCE_VARIABLE_REPO not set"
fi

###############################################
### VALIDATE REQUIRED VARIABLES
###############################################
required_vars=("SONAR_TOKEN" "SONAR_URL")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=($var)
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "[ERROR] The following required environment variables are missing: ${missing_vars[*]}"
    add_event "validate variables" "Failed" "Missing variables" "Missing: ${missing_vars[*]}"
    
    ERROR_EVENTS=$(echo "$EVENTS" | jq '[to_entries[] | select(.value.status == "Failed") | .key]')
    
    jq -n \
      --argjson events "$EVENTS" \
      --argjson error_events "$ERROR_EVENTS" \
      '{
        build: {
          status: false,
          reason: "Missing required variables",
          message: "SONAR_TOKEN or SONAR_URL not provided",
          events: $events,
          current_error: "Missing required variables",
          error_events: $error_events
        },
        events: $events,
        output_vars: {
          sonar_scan: {
            status: "Failed",
            reason: "Missing required variables",
            message: "SONAR_TOKEN or SONAR_URL not provided",
            current_error: "Missing required variables",
            error_events: $error_events
          }
        }
      }' > "${EXEC_DIR}/${SONAR_OUTPUT_FILE}"
    
    generateOutput ${ACTIVITY_SUB_TASK_CODE} false "Missing required variables"
    exit 1
fi

add_event "validate variables" "Successful" "All variables present" "SONAR_TOKEN and SONAR_URL validated"

logInfoMessage "Sonar Url: $SONAR_URL"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

###############################################
### DETERMINE SCAN SCOPE
###############################################
SONAR_SCAN_SCOPE=${SONAR_SCAN_SCOPE:-all}

if [ "$SONAR_SCAN_SCOPE" = "latest" ]; then
    CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | xargs)
    if [ -z "$CHANGED_FILES" ]; then
        logWarningMessage "No changed files found in the latest commit. Defaulting to scanning the whole codebase."
        SONAR_SOURCES="."
        add_event "determine scan scope" "Successful" "Scanning all files" "No changes detected, scanning full codebase"
    else
        logInfoMessage "Scanning only the latest changed files: $CHANGED_FILES"
        SONAR_SOURCES=$(echo $CHANGED_FILES | tr ' ' ',')
        add_event "determine scan scope" "Successful" "Scanning changed files" "Scanning: ${CHANGED_FILES}"
    fi
else
    logInfoMessage "Scanning the whole codebase."
    SONAR_SOURCES="."
    add_event "determine scan scope" "Successful" "Scanning all files" "Full codebase scan"
fi

###############################################
### DETECT LANGUAGE AND PREPARE ARGS
###############################################
prepareSonarScanArgs() {
  if [ -z "$LANGUAGE" ]; then
    if find . -name "*.java" | grep -q .; then
      LANGUAGE="java"
    elif find . -name "*.py" | grep -q .; then
      LANGUAGE="python"
    elif find . -name "*.go" | grep -q .; then
      LANGUAGE="go"
    elif find . -name "*.js" | grep -q .; then
      LANGUAGE="javascript"
    elif find . -name "*.php" | grep -q .; then
      LANGUAGE="php"
    else
      LANGUAGE="unknown"
      logWarningMessage "Unable to detect project language. Defaulting to basic source scan."
    fi
  else
    logInfoMessage "Language already provided: $LANGUAGE"
  fi

  case "$LANGUAGE" in
    java)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES} -Dsonar.java.binaries=${JAVA_BINARIES:-target/classes}"
      ;;
    python)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES} -Dsonar.python.version=${PYTHON_VERSION:-3}"
      ;;
    go)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES} -Dsonar.go.coverage.reportPaths=coverage.out"
      ;;
    javascript)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES} -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info"
      ;;
    php)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES} -Dsonar.language=php"
      if [ -f "coverage/clover.xml" ]; then
        SONAR_ARGS="$SONAR_ARGS -Dsonar.php.coverage.reportPaths=coverage/clover.xml"
      fi
      ;;
    *)
      SONAR_ARGS="$SONAR_ARGS -Dsonar.sources=${SONAR_SOURCES}"
      logWarningMessage "No specific SonarQube configuration for language '$LANGUAGE'. Using basic source scan."
      ;;
  esac
  
  add_event "detect language" "Successful" "Language detected" "Detected language: ${LANGUAGE}"
}

prepareSonarScanArgs

###############################################
### RUN SONARQUBE SCAN
###############################################
logInfoMessage "Executing Sonar Scan for $LANGUAGE: sonar-scanner -Dsonar.token=**** -Dsonar.host.url=$SONAR_URL -Dsonar.projectKey=$CODEBASE_DIR $SONAR_ARGS"

sonar-scanner -Dsonar.token="$SONAR_TOKEN" -Dsonar.host.url="$SONAR_URL" -Dsonar.projectKey="$CODEBASE_DIR" $SONAR_ARGS
TASK_STATUS=$?

if [[ "$TASK_STATUS" -eq 0 ]]; then
  add_event "sonar scan" "Successful" "Scan completed" "SonarQube scan executed successfully"
else
  add_event "sonar scan" "Failed" "Scan execution error" "sonar-scanner exited with code $TASK_STATUS"
fi

SONAR_GATE_CHECK=${SONAR_GATE_CHECK:-false}
localSleepDuration=${SLEEP_DURATION:-300}
SLEEP_DURATION=${SLEEP_DURATION:-30}

logInfoMessage "Waiting ${SLEEP_DURATION} seconds for SonarQube to process results..."
sleep $SLEEP_DURATION

###############################################
### FETCH SONARQUBE METRICS
###############################################
response=$(curl -s -w "%{http_code}" -u "$SONAR_TOKEN": -X GET "${SONAR_URL}/api/measures/component?component=$CODEBASE_DIR&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" -o response.json)

http_code=$(echo "$response" | tail -n1)
METRICS_FETCH_SUCCESS=1

if [ "$http_code" -eq 200 ]; then
    json=$(jq '.' response.json)
    logInfoMessage "Successfully fetched SonarQube metrics."
    add_event "fetch metrics" "Successful" "Metrics retrieved" "HTTP 200 - metrics fetched successfully"
else
    case "$http_code" in
        401) echo "[ERROR] Unauthorized. The SONAR_TOKEN might not have sufficient permissions." ;;
        403) echo "[ERROR] Forbidden. Access denied." ;;
        404) echo "[ERROR] Not Found. Check ${SONAR_URL} and ${CODEBASE_DIR}." ;;
        500) echo "[ERROR] Internal Server Error." ;;
        *) echo "[ERROR] Failed to fetch SonarQube metrics. HTTP Status Code: $http_code." ;;
    esac
    
    cat response.json
    METRICS_FETCH_SUCCESS=0
    add_event "fetch metrics" "Failed" "HTTP error ${http_code}" "Failed to fetch metrics from SonarQube"
fi

###############################################
### PROCESS METRICS AND CREATE CSV
###############################################
MI_SEND_STATUS=0

if [ $METRICS_FETCH_SUCCESS -eq 1 ]; then
    SONAR_CSV="${EXEC_DIR}/sonar_summary.csv"
    
    echo $json | jq -r '.component.measures | map({metric: .metric, value: .value}) | (map(.metric) | @csv), (map(.value) | @csv)' | sed 's/"//g' > "${SONAR_CSV}"
    
    if [ ! -f "${SONAR_CSV}" ]; then
        logErrorMessage "Failed to create ${SONAR_CSV}"
        add_event "generate csv report" "Failed" "File creation failed" "Could not create CSV report"
        MI_SEND_STATUS=1
    else
        logInfoMessage "Displaying SonarQube Summary Report"
        echo "================================================================================"
        python3 /opt/buildpiper/shell-functions/print_table.py "${SONAR_CSV}"
        echo "================================================================================"
        
        add_event "generate csv report" "Successful" "CSV created" "SonarQube summary CSV generated"
        
        export base64EncodedResponse=$(encodeFileContent "${SONAR_CSV}")
        
        ###############################################
        ### SEND MI DATA IF CONFIGURED
        ###############################################
        if [ -n "$MI_SERVER_ADDRESS" ]; then
            MI_SERVER_ADDRESS="${MI_SERVER_ADDRESS%/}" 
            for source_key in sonarqube_blocker_violations sonarqube_bugs sonarqube_security_rating sonarqube_code_smells sonarqube_major_violations; do
                logInfoMessage "Pushing '$source_key' metrics to MI server..."
                
                export application=$APPLICATION_NAME
                export environment=$environment
                export service=$service
                export organization=$ORGANIZATION
                export source_key=$source_key
                export report_file_path=$REPORT_FILE_PATH
                
                generateMIDataJson /opt/buildpiper/data/mi.template "${EXEC_DIR}/sonar.mi"
                
                if sendMIData "${EXEC_DIR}/sonar.mi" ${MI_SERVER_ADDRESS}; then
                    logInfoMessage "Successfully pushed '$source_key' metrics"
                    add_event "send mi ${source_key}" "Successful" "MI data sent" "${source_key} sent to ${MI_SERVER_ADDRESS}"
                else
                    logErrorMessage "Failed to push '$source_key' metrics"
                    add_event "send mi ${source_key}" "Failed" "MI send error" "Failed to send ${source_key}"
                    MI_SEND_STATUS=1
                fi
            done
        else
            logInfoMessage "MI_SERVER_ADDRESS not provided, skipping MI data push."
            add_event "send mi data" "Successful" "Not configured" "MI server not configured"
        fi
    fi
else
    MI_SEND_STATUS=1
fi

###############################################
### QUALITY GATE CHECK (IF ENABLED)
###############################################
if [ "$SONAR_GATE_CHECK" == "true" ]; then
    logInfoMessage "Waiting for Quality Gate Check for ${localSleepDuration} Seconds"
    sleep "$localSleepDuration"
    
    statusResponse=$(curl -s -u "$SONAR_TOKEN": "${SONAR_URL}/api/qualitygates/project_status?projectKey=$CODEBASE_DIR")
    
    if [ $? -ne 0 ]; then
        logInfoMessage "Failed to fetch SonarQube quality gate status!"
        add_event "quality gate check" "Failed" "API call failed" "Could not fetch quality gate status"
        TASK_STATUS=1
    else
        gateStatus=$(echo "$statusResponse" | jq -r .projectStatus.status)
        
        if [ "$gateStatus" == "ERROR" ]; then
            logInfoMessage "SonarQube quality gate failed!"
            add_event "quality gate check" "Failed" "Gate failed" "Quality gate status: ERROR"
            TASK_STATUS=1
        else
            logInfoMessage "SonarQube quality gate passed."
            add_event "quality gate check" "Successful" "Gate passed" "Quality gate status: ${gateStatus}"
        fi
    fi
else
    logInfoMessage "Skipping Quality Gates Test"
    add_event "quality gate check" "Successful" "Not configured" "Quality gate check disabled"
fi

###############################################
### DETERMINE FINAL STATUS
###############################################
FINAL_STATUS="Successful"
FINAL_REASON="Scan completed"
FINAL_MESSAGE="SonarQube scan completed successfully"

if [[ "$TASK_STATUS" -ne 0 ]]; then
  FINAL_STATUS="failed"
  FINAL_REASON="Scan or quality gate failed"
  FINAL_MESSAGE="SonarQube scan failed with exit code ${TASK_STATUS}"
fi

###############################################
### BUILD ERROR EVENTS LIST
###############################################
ERROR_EVENTS=$(echo "$EVENTS" | jq '[to_entries[] | select(.value.status == "Failed") | .key]')

###############################################
### MAP STATUS TO BOOLEAN
###############################################
if [[ "$FINAL_STATUS" == "Successful" ]]; then
  STATUS_BOOL="true"
else
  STATUS_BOOL="false"
fi

###############################################
### CREATE STRUCTURED OUTPUT JSON
###############################################
jq -n \
  --argjson events "$EVENTS" \
  --argjson error_events "$ERROR_EVENTS" \
  --argjson status_bool "$STATUS_BOOL" \
  --arg final_status "$FINAL_STATUS" \
  --arg final_reason "$FINAL_REASON" \
  --arg final_message "$FINAL_MESSAGE" \
  --arg sonar_url "${SONAR_URL}" \
  --arg project_key "${CODEBASE_DIR}" \
  --arg language "${LANGUAGE}" \
  --arg gate_check "${SONAR_GATE_CHECK}" \
  '{
    build: {
      status: $status_bool,
      reason: $final_reason,
      message: $final_message,
      events: $events,
      current_error: (if $status_bool == "false" then $final_reason else "" end),
      error_events: $error_events
    },
    events: $events,
    output_vars: {
      sonar_scan: {
        status: $final_status,
        reason: $final_reason,
        message: $final_message,
        scan: {
          sonar_url: $sonar_url,
          project_key: $project_key,
          language: $language,
          quality_gate_check: $gate_check
        },
        current_error: (if $final_status == "failed" then $final_reason else "" end),
        error_events: $error_events
      }
    }
  }' > "${EXEC_DIR}/${SONAR_OUTPUT_FILE}"

logInfoMessage "Output JSON written to ${EXEC_DIR}/${SONAR_OUTPUT_FILE}"
add_event "create output" "Successful" "Output file created" "Structured output written to ${SONAR_OUTPUT_FILE}"

###############################################
### SIGNAL PASS/FAIL TO BUILDPIPER PIPELINE
###############################################
if [ $TASK_STATUS -eq 0 ]; then
    if [ -z "$MI_SERVER_ADDRESS" ]; then
        logInfoMessage "Sonar scan succeeded. MI server not configured."
        generateOutput ${ACTIVITY_SUB_TASK_CODE} true "Sonar scan succeeded."
    elif [ $MI_SEND_STATUS -eq 0 ]; then
        logInfoMessage "Congratulations, Sonar scan succeeded and the report was successfully sent to the MI server!"
        generateOutput ${ACTIVITY_SUB_TASK_CODE} true "Sonar scan succeeded and report sent to MI server."
    else
        logWarningMessage "Sonar scan succeeded, but the report was not sent to the MI server."
        generateOutput ${ACTIVITY_SUB_TASK_CODE} false "Sonar scan succeeded, but MI send failed."
    fi
else
    logWarningMessage "Trivy scan failed, but the step is configured as NON-BLOCKING (warning mode).

  If you want the pipeline to FAIL on leaks:
  - Go to job template settings
  - Set VALIDATION_FAILURE_ACTION = FAILURE

  Current setting allows pipeline to continue."
    add_event "validation mode" "Successful" "Non-blocking validation" "Scan failed but pipeline continued because VALIDATION_FAILURE_ACTION is not FAILURE"
    generateOutput ${ACTIVITY_SUB_TASK_CODE} false "$FINAL_MESSAGE"  
fi

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}