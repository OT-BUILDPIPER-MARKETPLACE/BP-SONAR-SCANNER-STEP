#!/bin/bash
set -euo pipefail

# ==============================================================================
# Source BuildPiper Functions
# ==============================================================================
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/mi-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh
source /opt/buildpiper/shell-functions/getDataFile.sh
source getDynamicVars.sh

# ==============================================================================
# INITIALIZATION
# ==============================================================================
TASK_STATUS=0
MI_SEND_STATUS=1
METRICS_FETCH_SUCCESS=0

WORKSPACE="/bp/workspace"
SLEEP_DURATION="${SLEEP_DURATION:-30}"
EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"

OUTPUT_FILE="${ACTIVITY_SUB_TASK_CODE}_output.json"

mkdir -p "${EXEC_DIR}"
mkdir -p "${REPORTS_DIR}"

###############################################################################
# EVENTS TRACKING
###############################################################################
EVENTS='{}'

add_event() {
    local key="${1:-}"
    local status="${2:-}"
    local reason="${3:-}"
    local message="${4:-}"

    if [ -z "$key" ] || [ -z "$status" ]; then
        echo "add_event(): key/status missing"
        return 1
    fi

    key="$(echo "$key" | tr '_' ' ' | tr '-' ' ' | tr '[:upper:]' '[:lower:]')"

    EVENTS=$(jq \
        --arg k "$key" \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg message "$message" \
        '. + {
            ($k): {
                status: $status,
                reason: $reason,
                message: $message
            }
        }' <<< "$EVENTS")
}

###############################################################################
# ENVIRONMENT
###############################################################################
environment="${PROJECT_ENV_NAME:-$(getProjectEnv)}"
service="${COMPONENT_NAME:-$(getServiceName)}"

add_event \
    "initialize task" \
    "Successful" \
    "Sonar scan initialization" \
    "Task initialized successfully"

add_event \
    "create execution dir" \
    "Successful" \
    "Execution directory created" \
    "${EXEC_DIR}"

logInfoMessage "=============================================================="
logInfoMessage "Starting SonarQube Scan"
logInfoMessage "=============================================================="

logInfoMessage "Workspace       : ${WORKSPACE}"
logInfoMessage "Codebase        : ${CODEBASE_LOCATION}"
logInfoMessage "Reports         : ${REPORTS_DIR}"
logInfoMessage "Execution Dir   : ${EXEC_DIR}"
logInfoMessage "Environment     : ${environment}"
logInfoMessage "Service         : ${service}"

###############################################################################
# SONAR SCANNER VERSION
###############################################################################
set +e

SONAR_VERSION_OUTPUT=$(sonar-scanner --version 2>&1)
SONAR_VERSION_STATUS=$?

set -e

if [[ ${SONAR_VERSION_STATUS} -eq 0 ]]; then

    logInfoMessage "${SONAR_VERSION_OUTPUT}"

    add_event \
        "verify sonar scanner" \
        "Successful" \
        "SonarScanner verified" \
        "${SONAR_VERSION_OUTPUT}"

else

    logErrorMessage "Unable to execute sonar-scanner."

    add_event \
        "verify sonar scanner" \
        "Failed" \
        "SonarScanner unavailable" \
        "${SONAR_VERSION_OUTPUT}"

    TASK_STATUS=1
fi

###############################################################################
# LOG SCAN LOCATION
###############################################################################
logInfoMessage "I'll scan the code available at [${WORKSPACE}] and mounted at [${CODEBASE_DIR}]"

add_event \
    "verify codebase" \
    "Successful" \
    "Codebase location identified" \
    "${CODEBASE_LOCATION}"

###############################################################################
# JAVA BINARIES SUGGESTION
###############################################################################
if [ "${JAVA_BINARIES:-}" = "target/classes" ]; then

    logInfoMessage "[SUGGESTION] The JAVA_BINARIES variable is currently set to the default value of 'target/classes'."
    logInfoMessage "[SUGGESTION] If your compiled Java classes are located in a different directory, set JAVA_BINARIES accordingly."
    logInfoMessage "[SUGGESTION] Example: export JAVA_BINARIES=target/classes"

    add_event \
        "java binaries configuration" \
        "Successful" \
        "Default Java binaries location used" \
        "JAVA_BINARIES=target/classes"

else

    logInfoMessage "Using JAVA_BINARIES set to: ${JAVA_BINARIES:-target/classes}"

    add_event \
        "java binaries configuration" \
        "Successful" \
        "Java binaries configuration detected" \
        "JAVA_BINARIES=${JAVA_BINARIES:-target/classes}"

fi

###############################################################################
# CHANGE DIRECTORY
###############################################################################
cd "${CODEBASE_LOCATION}"

add_event \
    "change codebase directory" \
    "Successful" \
    "Changed to codebase directory" \
    "${CODEBASE_LOCATION}"

logInfoMessage "I've received the following arguments: [$*]"

###############################################################################
# FETCH SONAR DETAILS
###############################################################################
if [ -n "${SOURCE_VARIABLE_REPO:-}" ]; then

    if [ -n "${SONAR_TOKEN:-}" ] && [ -n "${SONAR_URL:-}" ]; then

        logInfoMessage "SONAR_TOKEN and SONAR_URL are provided. Skipping fetching details from SOURCE_VARIABLE_REPO."

        add_event \
            "fetch sonar details" \
            "Successful" \
            "Sonar configuration already available" \
            "SONAR_TOKEN and SONAR_URL are configured"

    else

        logInfoMessage "Fetching details from ${SOURCE_VARIABLE_REPO} because SONAR_TOKEN or SONAR_URL is not provided."

        set +e

        fetch_service_details
        FETCH_STATUS=$?

        set -e

        if [[ ${FETCH_STATUS} -eq 0 ]]; then

            add_event \
                "fetch sonar details" \
                "Successful" \
                "Sonar details fetched" \
                "Sonar configuration fetched from SOURCE_VARIABLE_REPO"

        else

            add_event \
                "fetch sonar details" \
                "Failed" \
                "Unable to fetch Sonar details" \
                "fetch_service_details exited with ${FETCH_STATUS}"

            TASK_STATUS=1

        fi

    fi

else

    logInfoMessage "SOURCE_VARIABLE_REPO is not set. Skipping fetch operation."

    add_event \
        "fetch sonar details" \
        "Skipped" \
        "Source variable repository not configured" \
        "SOURCE_VARIABLE_REPO is not set"

fi

###############################################################################
# REQUIRED ENVIRONMENT VARIABLES
###############################################################################
required_vars=("SONAR_TOKEN" "SONAR_URL")
missing_vars=()

for var in "${required_vars[@]}"; do

    if [ -z "${!var:-}" ]; then
        missing_vars+=("$var")
    fi

done

if [ ${#missing_vars[@]} -ne 0 ]; then

    logErrorMessage "The following required environment variables are missing: ${missing_vars[*]}"

    add_event \
        "validate required variables" \
        "Failed" \
        "Required environment variables missing" \
        "${missing_vars[*]}"

    TASK_STATUS=1

    ERROR_EVENTS=$(echo "$EVENTS" | jq '[to_entries[] | select(.value.status=="Failed") | .key]')

    jq -n \
        --argjson events "$EVENTS" \
        --argjson error_events "$ERROR_EVENTS" \
        '{
            build:{
                status:false,
                reason:"Required environment variables missing",
                message:"Required SonarQube configuration is missing",
                events:$events,
                current_error:"Required environment variables missing",
                error_events:$error_events
            },
            events:$events,
            output_vars:{
                sonar_scan:{
                    status:"Failed",
                    reason:"Required environment variables missing",
                    message:"Required SonarQube configuration is missing",
                    current_error:"Required environment variables missing",
                    error_events:$error_events
                }
            }
        }' > "${EXEC_DIR}/${OUTPUT_FILE}"

    generateOutput \
        "${ACTIVITY_SUB_TASK_CODE}" \
        false \
        "Required environment variables missing: ${missing_vars[*]}"

    saveTaskStatus "${TASK_STATUS}" "${ACTIVITY_SUB_TASK_CODE}"

    exit 1

else

    add_event \
        "validate required variables" \
        "Successful" \
        "Required variables available" \
        "SONAR_TOKEN and SONAR_URL are configured"

fi

###############################################################################
# SONAR URL
###############################################################################
logInfoMessage "Sonar Url: ${SONAR_URL}"

add_event \
    "verify sonar url" \
    "Successful" \
    "SonarQube URL configured" \
    "${SONAR_URL}"

###############################################################################
# CURRENT BRANCH
###############################################################################
set +e

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
BRANCH_STATUS=$?

set -e

if [[ ${BRANCH_STATUS} -eq 0 ]]; then

    logInfoMessage "Current branch: ${CURRENT_BRANCH}"

    add_event \
        "detect git branch" \
        "Successful" \
        "Git branch detected" \
        "${CURRENT_BRANCH}"

else

    CURRENT_BRANCH="unknown"

    logWarningMessage "Unable to determine current Git branch."

    add_event \
        "detect git branch" \
        "Failed" \
        "Git branch detection failed" \
        "Unable to determine current branch"

fi

###############################################################################
# SONAR SCAN SCOPE
###############################################################################
SONAR_SCAN_SCOPE="${SONAR_SCAN_SCOPE:-all}"

if [ "${SONAR_SCAN_SCOPE}" = "latest" ]; then

    logInfoMessage "Sonar scan scope configured as latest commit."

    set +e

    CHANGED_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | xargs)
    CHANGED_FILES_STATUS=$?

    set -e

    if [ -z "${CHANGED_FILES}" ]; then

        logWarningMessage "No changed files found in the latest commit. Defaulting to scanning the whole codebase."

        SONAR_SOURCES="."

        add_event \
            "prepare scan scope" \
            "Successful" \
            "No changed files found" \
            "Defaulting to scanning the whole codebase"

    else

        logInfoMessage "Scanning only the latest changed files: ${CHANGED_FILES}"

        SONAR_SOURCES=$(echo "${CHANGED_FILES}" | tr ' ' ',')

        add_event \
            "prepare scan scope" \
            "Successful" \
            "Latest commit scope selected" \
            "Scanning changed files: ${SONAR_SOURCES}"

    fi

else

    logInfoMessage "Scanning the whole codebase."

    SONAR_SOURCES="."

    add_event \
        "prepare scan scope" \
        "Successful" \
        "Full codebase scope selected" \
        "SONAR_SCAN_SCOPE=${SONAR_SCAN_SCOPE}"

fi

###############################################################################
# PREPARE SONAR ARGUMENTS
###############################################################################
SONAR_ARGS=""

prepareSonarScanArgs() {

    if [ -z "${LANGUAGE:-}" ]; then

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

        logInfoMessage "Language already provided: ${LANGUAGE}"

    fi

    case "${LANGUAGE}" in

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

            logWarningMessage "No specific SonarQube configuration for language '${LANGUAGE}'. Using basic source scan."

            ;;

    esac
}

prepareSonarScanArgs

logInfoMessage "Detected language: ${LANGUAGE}"
logInfoMessage "Sonar sources: ${SONAR_SOURCES}"
logInfoMessage "Sonar arguments: ${SONAR_ARGS}"

add_event \
    "prepare sonar arguments" \
    "Successful" \
    "Sonar scan arguments prepared" \
    "Language=${LANGUAGE}, Sources=${SONAR_SOURCES}"

###############################################################################
# QUALITY GATE CONFIGURATION
###############################################################################
SONAR_GATE_CHECK="${SONAR_GATE_CHECK:-false}"
SONAR_QUALITY_GATE_TIMEOUT="${SONAR_QUALITY_GATE_TIMEOUT:-300}"
SONAR_WEB_SERVICE_TIMEOUT="${SONAR_WEB_SERVICE_TIMEOUT:-300}"

if [ "${SONAR_GATE_CHECK}" = "true" ]; then

    case "${SONAR_QUALITY_GATE_TIMEOUT}:${SONAR_WEB_SERVICE_TIMEOUT}" in
        *[!0-9:]*|:*|*:|0:*|*:0)

            logErrorMessage "SONAR_QUALITY_GATE_TIMEOUT and SONAR_WEB_SERVICE_TIMEOUT must be positive integers."

            add_event \
                "validate quality gate configuration" \
                "Failed" \
                "Invalid quality gate timeout" \
                "SONAR_QUALITY_GATE_TIMEOUT=${SONAR_QUALITY_GATE_TIMEOUT}, SONAR_WEB_SERVICE_TIMEOUT=${SONAR_WEB_SERVICE_TIMEOUT}"

            TASK_STATUS=1

            ;;

        *)

            SONAR_ARGS="$SONAR_ARGS -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=${SONAR_QUALITY_GATE_TIMEOUT} -Dsonar.ws.timeout=${SONAR_WEB_SERVICE_TIMEOUT}"

            logInfoMessage "Quality Gate enforcement enabled."
            logInfoMessage "Gate timeout: ${SONAR_QUALITY_GATE_TIMEOUT}s"
            logInfoMessage "Web service timeout: ${SONAR_WEB_SERVICE_TIMEOUT}s"

            add_event \
                "quality gate configuration" \
                "Successful" \
                "Quality Gate enforcement enabled" \
                "Gate timeout=${SONAR_QUALITY_GATE_TIMEOUT}s, Web timeout=${SONAR_WEB_SERVICE_TIMEOUT}s"

            ;;

    esac

else

    logInfoMessage "Quality Gate enforcement disabled."

    add_event \
        "quality gate configuration" \
        "Skipped" \
        "Quality Gate enforcement disabled" \
        "SONAR_GATE_CHECK=${SONAR_GATE_CHECK}"

fi

###############################################################################
# RUN SONAR SCANNER
###############################################################################
logInfoMessage "Executing Sonar Scan for ${LANGUAGE}: sonar-scanner -Dsonar.token=**** -Dsonar.host.url=${SONAR_URL} -Dsonar.projectKey=${CODEBASE_DIR} ${SONAR_ARGS}"

set +e

sonar-scanner \
    -Dsonar.token="${SONAR_TOKEN}" \
    -Dsonar.host.url="${SONAR_URL}" \
    -Dsonar.projectKey="${CODEBASE_DIR}" \
    ${SONAR_ARGS}

SONAR_STATUS=$?

set -e

TASK_STATUS=${SONAR_STATUS}

if [[ ${SONAR_STATUS} -eq 0 ]]; then

    logInfoMessage "SonarQube scan completed successfully."

    add_event \
        "sonar scan" \
        "Successful" \
        "SonarQube scan completed" \
        "SonarScanner exited with status 0"

else

    logErrorMessage "SonarQube scan failed with exit code ${SONAR_STATUS}."

    add_event \
        "sonar scan" \
        "Failed" \
        "SonarQube scan failed" \
        "SonarScanner exited with status ${SONAR_STATUS}"

fi

###############################################################################
# WAIT FOR SONAR DATA
###############################################################################
logInfoMessage "Waiting ${SLEEP_DURATION} seconds before fetching SonarQube metrics."

sleep "${SLEEP_DURATION}"

add_event \
    "wait for sonar metrics" \
    "Successful" \
    "Wait completed" \
    "Waited ${SLEEP_DURATION} seconds"

###############################################################################
# FETCH SONARQUBE METRICS
###############################################################################
RESPONSE_FILE="${REPORTS_DIR}/response.json"

logInfoMessage "Fetching SonarQube metrics."

set +e

response=$(curl \
    -s \
    -w "%{http_code}" \
    -u "${SONAR_TOKEN}:" \
    -X GET \
    "${SONAR_URL}/api/measures/component?component=${CODEBASE_DIR}&metricKeys=ncloc,lines,files,classes,functions,complexity,violations,blocker_violations,critical_violations,major_violations,minor_violations,info_violations,code_smells,bugs,reliability_rating,security_rating,sqale_index,duplicated_lines,duplicated_blocks,duplicated_files,duplicated_lines_density,sqale_rating&format=json" \
    -o "${RESPONSE_FILE}")

CURL_STATUS=$?

set -e

http_code=$(echo "${response}" | tail -n1)

if [[ ${CURL_STATUS} -ne 0 ]]; then

    logErrorMessage "curl failed while fetching SonarQube metrics."

    add_event \
        "fetch sonar metrics" \
        "Failed" \
        "SonarQube metrics request failed" \
        "curl exited with status ${CURL_STATUS}"

    METRICS_FETCH_SUCCESS=0

else

    if [ "${http_code}" -eq 200 ]; then

        if jq -e '.component.measures | type == "array" and length > 0' "${RESPONSE_FILE}" >/dev/null 2>&1; then

            logInfoMessage "Successfully fetched SonarQube metrics."

            add_event \
                "fetch sonar metrics" \
                "Successful" \
                "SonarQube metrics fetched" \
                "HTTP ${http_code}, component.measures available"

            METRICS_FETCH_SUCCESS=1

        else

            logErrorMessage "SonarQube returned HTTP 200, but component.measures is missing or empty."
            logErrorMessage "SonarQube metrics response: $(jq -c '.' "${RESPONSE_FILE}" 2>/dev/null || tr '\n' ' ' < "${RESPONSE_FILE}")"

            add_event \
                "fetch sonar metrics" \
                "Failed" \
                "Metrics response invalid" \
                "HTTP 200 received but component.measures is missing or empty"

            METRICS_FETCH_SUCCESS=0

        fi

    else

        case "${http_code}" in

            401)
                ERROR_MESSAGE="Unauthorized. SONAR_TOKEN might not have sufficient permissions."
                ;;

            403)
                ERROR_MESSAGE="Forbidden. SONAR_TOKEN does not have required permissions."
                ;;

            404)
                ERROR_MESSAGE="Not Found. Check SONAR_URL and CODEBASE_DIR."
                ;;

            500)
                ERROR_MESSAGE="Internal Server Error on SonarQube server."
                ;;

            *)
                ERROR_MESSAGE="Failed to fetch SonarQube metrics. HTTP Status Code: ${http_code}."
                ;;

        esac

        logErrorMessage "${ERROR_MESSAGE}"

        echo "[DEBUG] Response received:"
        cat "${RESPONSE_FILE}"

        add_event \
            "fetch sonar metrics" \
            "Failed" \
            "SonarQube metrics request failed" \
            "${ERROR_MESSAGE}"

        METRICS_FETCH_SUCCESS=0

    fi

fi

###############################################################################
# GENERATE SONAR SUMMARY
###############################################################################
SUMMARY_REPORT="${REPORTS_DIR}/sonar_summary.csv"

if [ "${METRICS_FETCH_SUCCESS}" -eq 1 ]; then

    logInfoMessage "Generating SonarQube summary report."

    if jq -e -r '
        .component.measures
        | if type != "array" or length == 0
          then error("component.measures is missing or empty")
          else .
          end
        | (map({key: .metric, value: (.value // "")}) | from_entries) as $values
        | [
            "blocker_violations",
            "ncloc",
            "lines",
            "files",
            "bugs",
            "classes",
            "functions",
            "complexity",
            "violations",
            "critical_violations",
            "minor_violations",
            "security_rating",
            "info_violations",
            "reliability_rating",
            "code_smells",
            "sqale_index",
            "duplicated_lines",
            "duplicated_blocks",
            "duplicated_files",
            "duplicated_lines_density",
            "major_violations",
            "sqale_rating"
          ] as $metric_order
        | ($metric_order | join(",")),
          ($metric_order | map($values[.] // "" | tostring) | join(","))
    ' "${RESPONSE_FILE}" > "${SUMMARY_REPORT}" && [ -s "${SUMMARY_REPORT}" ]; then

        logInfoMessage "SonarQube summary report generated: ${SUMMARY_REPORT}"

        add_event \
            "generate summary report" \
            "Successful" \
            "Sonar summary generated" \
            "${SUMMARY_REPORT}"

    else

        logErrorMessage "Failed to create a non-empty SonarQube summary report."

        add_event \
            "generate summary report" \
            "Failed" \
            "Summary report generation failed" \
            "${SUMMARY_REPORT}"

        METRICS_FETCH_SUCCESS=0

    fi

else

    logWarningMessage "Skipping SonarQube summary generation because metrics were not fetched."

    add_event \
        "generate summary report" \
        "Skipped" \
        "SonarQube metrics unavailable" \
        "Summary report was not generated"

fi

###############################################################################
# DISPLAY SUMMARY
###############################################################################
if [ -f "${SUMMARY_REPORT}" ]; then

    logInfoMessage "Displaying SonarQube Summary Report."

    echo "================================================================================"
    python3 /opt/buildpiper/shell-functions/print_table.py "${SUMMARY_REPORT}"
    echo "================================================================================"

    add_event \
        "display summary report" \
        "Successful" \
        "Summary report displayed" \
        "${SUMMARY_REPORT}"

else

    add_event \
        "display summary report" \
        "Skipped" \
        "Summary report unavailable" \
        "${SUMMARY_REPORT}"

fi

###############################################################################
# COPY REPORTS
###############################################################################
if [ -f "${SUMMARY_REPORT}" ]; then

    logInfoMessage "Updating reports in ${EXEC_DIR}"

    cp -rf "${REPORTS_DIR}"/* "${EXEC_DIR}/"

    add_event \
        "copy reports" \
        "Successful" \
        "Reports copied" \
        "Reports copied to ${EXEC_DIR}"

else

    add_event \
        "copy reports" \
        "Skipped" \
        "No reports available" \
        "No SonarQube summary report to copy"

fi

###############################################################################
# MI DATA
###############################################################################
if [ -f "${SUMMARY_REPORT}" ]; then

    export base64EncodedResponse=$(encodeFileContent "${SUMMARY_REPORT}")

    add_event \
        "prepare mi report" \
        "Successful" \
        "MI report prepared" \
        "${SUMMARY_REPORT}"

else

    add_event \
        "prepare mi report" \
        "Skipped" \
        "Summary report unavailable" \
        "Unable to prepare MI report"

fi

###############################################################################
# SEND DATA TO MI
###############################################################################
if [ -n "${MI_SERVER_ADDRESS:-}" ] && [ -f "${SUMMARY_REPORT}" ]; then

    MI_SEND_STATUS=0

    for source_key in \
        sonarqube_blocker_violations \
        sonarqube_bugs \
        sonarqube_security_rating \
        sonarqube_code_smells \
        sonarqube_major_violations
    do

        logInfoMessage "Initiating MI data push for '${source_key}'."

        export application="${APPLICATION_NAME}"
        export environment="${environment}"
        export service="${service}"
        export organization="${ORGANIZATION}"
        export source_key="${source_key}"
        export report_file_path="${REPORT_FILE_PATH}"
        export url_details="${URL_DETAILS}"

        MI_FILE="${EXEC_DIR}/sonar_${source_key}.mi"

        if generateMIDataJson \
            /opt/buildpiper/data/mi.template \
            "${MI_FILE}"; then

            logInfoMessage "Generated MI payload for ${source_key}."

            add_event \
                "generate mi data ${source_key}" \
                "Successful" \
                "MI payload generated" \
                "${MI_FILE}"

        else

            logErrorMessage "Failed to generate MI payload for ${source_key}."

            add_event \
                "generate mi data ${source_key}" \
                "Failed" \
                "MI payload generation failed" \
                "${source_key}"

            MI_SEND_STATUS=1
            continue

        fi

        logInfoMessage "Sonar Scanning JSON to be sent to MI server."
        cat "${MI_FILE}"

        if sendMIData "${MI_FILE}" "${MI_SERVER_ADDRESS}"; then

            logInfoMessage "Successfully completed MI data push for '${source_key}'."

            add_event \
                "send mi data ${source_key}" \
                "Successful" \
                "Summary uploaded" \
                "MI data successfully uploaded for ${source_key}"

        else

            logErrorMessage "Failed to push data for '${source_key}'."

            add_event \
                "send mi data ${source_key}" \
                "Failed" \
                "MI upload failed" \
                "Unable to upload data for ${source_key}"

            MI_SEND_STATUS=1

        fi

    done

elif [ -z "${MI_SERVER_ADDRESS:-}" ]; then

    logInfoMessage "MI_SERVER_ADDRESS not provided. Skipping MI data push."

    MI_SEND_STATUS=0

    add_event \
        "send mi data" \
        "Skipped" \
        "MI server not configured" \
        "MI_SERVER_ADDRESS is not configured"

else

    logWarningMessage "Sonar summary report unavailable. Skipping MI data push."

    MI_SEND_STATUS=1

    add_event \
        "send mi data" \
        "Skipped" \
        "Summary report unavailable" \
        "SonarQube metrics were not available"

fi

###############################################################################
# FINAL STATUS
###############################################################################
FINAL_STATUS="Successful"
FINAL_REASON="Sonar scan completed successfully"
FINAL_MESSAGE="Sonar scan completed successfully"

if [ "${TASK_STATUS}" -ne 0 ]; then

    FINAL_STATUS="Failed"
    FINAL_REASON="Sonar scan failed"
    FINAL_MESSAGE="Sonar scan failed with exit code ${TASK_STATUS}"

fi

if [ "${TASK_STATUS}" -eq 0 ]; then

    if [ -z "${MI_SERVER_ADDRESS:-}" ]; then

        FINAL_REASON="Sonar scan successful; MI not configured"
        FINAL_MESSAGE="Sonar scan succeeded. MI server not configured, skipping report send."

    elif [ "${MI_SEND_STATUS}" -eq 0 ]; then

        FINAL_REASON="Sonar scan and MI upload successful"
        FINAL_MESSAGE="Sonar scan succeeded and the report was successfully sent to the MI server."

    else

        FINAL_REASON="Sonar scan successful but MI upload failed"
        FINAL_MESSAGE="Sonar scan succeeded, but the report was not sent to the MI server."

    fi

else

    if [ -z "${MI_SERVER_ADDRESS:-}" ]; then

        FINAL_REASON="Sonar scan failed; MI not configured"
        FINAL_MESSAGE="Sonar scan failed. MI server not configured, so metrics were not sent."

    elif [ "${MI_SEND_STATUS}" -eq 0 ]; then

        FINAL_REASON="Sonar scan failed but MI upload successful"
        FINAL_MESSAGE="Sonar scan failed, but the available metrics were successfully sent to the MI server."

    else

        FINAL_REASON="Sonar scan and MI upload failed"
        FINAL_MESSAGE="Sonar scan failed, and the metrics were not sent to the MI server."

    fi

fi

add_event \
    "final validation" \
    "$(
        if [ "${TASK_STATUS}" -eq 0 ]; then
            echo "Successful"
        else
            echo "Failed"
        fi
    )" \
    "${FINAL_REASON}" \
    "${FINAL_MESSAGE}"

###############################################################################
# ERROR EVENTS
###############################################################################
ERROR_EVENTS=$(
    echo "${EVENTS}" |
    jq '[to_entries[] | select(.value.status=="Failed") | .key]'
)

###############################################################################
# STATUS BOOLEAN
###############################################################################
STATUS_BOOL=true

if [ "${TASK_STATUS}" -ne 0 ]; then
    STATUS_BOOL=false
fi

###############################################################################
# CREATE OUTPUT JSON
###############################################################################
jq -n \
    --argjson events "${EVENTS}" \
    --argjson error_events "${ERROR_EVENTS}" \
    --argjson status "${STATUS_BOOL}" \
    --arg final_status "${FINAL_STATUS}" \
    --arg final_reason "${FINAL_REASON}" \
    --arg final_message "${FINAL_MESSAGE}" \
    --arg task_status "${TASK_STATUS}" \
    --arg mi_status "${MI_SEND_STATUS}" \
    --arg metrics_status "${METRICS_FETCH_SUCCESS}" \
    --arg sonar_url "${SONAR_URL}" \
    --arg project_key "${CODEBASE_DIR}" \
    --arg language "${LANGUAGE}" \
    --arg branch "${CURRENT_BRANCH}" \
    --arg scan_scope "${SONAR_SCAN_SCOPE}" \
'
{
    build:{
        status:$status,
        reason:$final_reason,
        message:$final_message,
        events:$events,
        current_error:(if $status then "" else $final_reason end),
        error_events:$error_events
    },

    events:$events,

    output_vars:{

        sonar_scan:{

            status:$final_status,
            reason:$final_reason,
            message:$final_message,

            results:{
                task_status:($task_status|tonumber),
                metrics_fetch_status:($metrics_status|tonumber),
                mi_send_status:($mi_status|tonumber),

                sonar:{
                    url:$sonar_url,
                    project_key:$project_key,
                    language:$language,
                    branch:$branch,
                    scan_scope:$scan_scope
                }
            },

            current_error:(if $status then "" else $final_reason end),
            error_events:$error_events

        }

    }

}
' > "${EXEC_DIR}/${OUTPUT_FILE}"

add_event \
    "create output" \
    "Successful" \
    "Output JSON created" \
    "${EXEC_DIR}/${OUTPUT_FILE}"

###############################################################################
# RECREATE OUTPUT JSON AFTER FINAL EVENT
###############################################################################
ERROR_EVENTS=$(
    echo "${EVENTS}" |
    jq '[to_entries[] | select(.value.status=="Failed") | .key]'
)

jq -n \
    --argjson events "${EVENTS}" \
    --argjson error_events "${ERROR_EVENTS}" \
    --argjson status "${STATUS_BOOL}" \
    --arg final_status "${FINAL_STATUS}" \
    --arg final_reason "${FINAL_REASON}" \
    --arg final_message "${FINAL_MESSAGE}" \
    --arg task_status "${TASK_STATUS}" \
    --arg mi_status "${MI_SEND_STATUS}" \
    --arg metrics_status "${METRICS_FETCH_SUCCESS}" \
    --arg sonar_url "${SONAR_URL}" \
    --arg project_key "${CODEBASE_DIR}" \
    --arg language "${LANGUAGE}" \
    --arg branch "${CURRENT_BRANCH}" \
    --arg scan_scope "${SONAR_SCAN_SCOPE}" \
'
{
    build:{
        status:$status,
        reason:$final_reason,
        message:$final_message,
        events:$events,
        current_error:(if $status then "" else $final_reason end),
        error_events:$error_events
    },

    events:$events,

    output_vars:{
        sonar_scan:{
            status:$final_status,
            reason:$final_reason,
            message:$final_message,

            results:{
                task_status:($task_status|tonumber),
                metrics_fetch_status:($metrics_status|tonumber),
                mi_send_status:($mi_status|tonumber),

                sonar:{
                    url:$sonar_url,
                    project_key:$project_key,
                    language:$language,
                    branch:$branch,
                    scan_scope:$scan_scope
                }
            },

            current_error:(if $status then "" else $final_reason end),
            error_events:$error_events
        }
    }
}
' > "${EXEC_DIR}/${OUTPUT_FILE}"

###############################################################################
# PIPELINE RESULT
###############################################################################
if [ "${TASK_STATUS}" -eq 0 ]; then

    logInfoMessage "${FINAL_MESSAGE}"

    generateOutput \
        "${ACTIVITY_SUB_TASK_CODE}" \
        true \
        "${FINAL_MESSAGE}"

elif [ "${VALIDATION_FAILURE_ACTION:-FAILURE}" = "FAILURE" ]; then

    logErrorMessage "${FINAL_MESSAGE}"

    generateOutput \
        "${ACTIVITY_SUB_TASK_CODE}" \
        false \
        "${FINAL_MESSAGE}"

    saveTaskStatus "${TASK_STATUS}" "${ACTIVITY_SUB_TASK_CODE}"

    if [ "${SONAR_GATE_CHECK}" = "true" ]; then
        exit "${TASK_STATUS}"
    fi

else

    logWarningMessage "
Sonar scan failed but the step is configured as NON-BLOCKING.

To fail the pipeline:
  - Set VALIDATION_FAILURE_ACTION=FAILURE

Current configuration allows the pipeline to continue.
"

    add_event \
        "validation mode" \
        "Successful" \
        "Non-blocking validation" \
        "Pipeline continued because VALIDATION_FAILURE_ACTION is not FAILURE"

    generateOutput \
        "${ACTIVITY_SUB_TASK_CODE}" \
        false \
        "${FINAL_MESSAGE}"

fi

###############################################################################
# SAVE TASK STATUS
###############################################################################
saveTaskStatus "${TASK_STATUS}" "${ACTIVITY_SUB_TASK_CODE}"