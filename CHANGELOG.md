# Changelog


### Changelog for `registry.buildpiper.in/okts/sonar-scan:dynamic-vars`

- **[NEW]**
    - Added dynamic variable handling
    - Added gatecheck handling

### Changelog for `registry.buildpiper.in/okts/sonar-scan:0.5-mi`

- **[NEW]** Added script for Java and Maven version switching based on `JAVA_VERSION` and `MAVEN_VERSION` environment variables.
- **[IMPROVED]** Docker setup with multiple JDK and Maven versions, making it easy to switch between them dynamically.
- **[FIXED]** Added checks for unsupported versions, providing clear feedback to users.
- **[DOCS]** Updated documentation for the new entrypoint script and environment variable configuration examples.

#### **[Added]**
- Integrated SonarQube scanner functionality to scan code available at specified workspace.
- Implemented logic to fetch service details based on defined environment variables.
- Added support for checking required environment variables (`SONAR_TOKEN`, `SONAR_URL`, `APPLICATION_NAME`, `ORGANIZATION`, `MI_SERVER_ADDRESS`) before execution.
- Introduced logic to handle SonarQube quality gate checks with configurable sleep duration.
- Enhanced error handling for HTTP status codes during SonarQube metrics fetching.
- Added metrics fetching logic and exporting to `reports/sonar_summary.csv`.

#### **[Changed]**
- Updated logging to provide clearer information regarding script execution and potential issues.
- Streamlined the process for pushing metrics data to the Maturity Dashboard for various SonarQube metrics.
- Updated `sendMIData` function in `mi-functions.sh`:
    - Enhanced logging capabilities to capture the HTTP response and status from the `curl` command.
    - Added error handling to log a detailed message if the data sending fails.
    - The function now echoes the sending status and response, improving traceability during execution.

    #### **[Details]**
        The updated `sendMIData` function provides better visibility into the HTTP request process, allowing for easier debugging of data sending to the MI server. It captures both the output and the status of the `curl` command, ensuring that any errors encountered during execution are logged for analysis.

#### **[Fixed]**
- Corrected handling of default values for `SLEEP_DURATION` and `JAVA_BINARIES` environment variables.
- Ensured that the script checks for the existence of required directories before creating files.