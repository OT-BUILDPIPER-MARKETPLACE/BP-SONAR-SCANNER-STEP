# BP-SONAR-SCANNER-STEP
A BP step to perform SonarQube scanning.

## Setup

1. **Clone the Repository**
   ```bash
   git clone https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-SONAR-SCANNER-STEP
   ```

2. **Build the Docker Image**
   ```bash
   cd BP-SONAR-SCANNER-STEP
   git submodule init
   git submodule update
   docker build -t registry.buildpiper.in/okts/sonar-scan:tag .
   ```
   **Note:** Please use the `v0.7` branch for `BP-BASE-SHELL-STEPS`.

3. **Local Testing**

   - **Testing SonarQube Scanner CLI:**
     ```bash
     sonar-scanner -Dsonar.login=<token> -Dsonar.host.url=https://sonarcloud.io/ -Dsonar.projectKey=<project-key> -Dsonar.organization=<org-key> -Dsonar.java.binaries=target
     ```

   - **Running Docker with Sonar Scanner CLI:**
     ```bash
     docker run -it --rm -v $PWD:/src -e WORKSPACE=/ -e CODEBASE_DIR=src -e APPLICATION_NAME=<application_name> -e ORGANIZATION=<organization_name> -e SOURCE_KEY=<source_key> -e REPORT_FILE_PATH=<report_file_path> -e MI_SERVER_ADDRESS=<mi_server_address> ot/sonar_scanner:0.1 " -Dsonar.login=<token> -Dsonar.host.url=https://sonarcloud.io/ -Dsonar.projectKey=<project-key> -Dsonar.organization=<org-key> -Dsonar.java.binaries=target"
     ```

   - **Preferred Method:**
     ```bash
     docker run -it --rm -v $PWD:/src -e WORKSPACE=/ -e CODEBASE_DIR=src ot/sonar_scanner:0.1 " -Dsonar.login=<token> -Dproject.settings=sonar.properties"
     ```

## Script Changes

The updated script now includes enhanced error handling and reporting. Key improvements:

1. **Error Handling and Debugging:**
   - The script now checks HTTP status codes to handle various error scenarios when fetching SonarQube metrics.
   - Added detailed logging for errors including unauthorized access, forbidden access, and server errors.

2. **Conditional Logging:**
   - The script logs a success message if both the SonarQube scan and the report publication to the MI server succeed.
   - If only the SonarQube scan succeeds but the report fails to send, it logs a warning indicating the report was not sent.
   - If the SonarQube scan fails, it logs an error and exits with a status code indicating failure.

3. **Summary Report Generation:**
   - Processes the SonarQube metrics and generates a CSV summary.
   - Logs and handles file creation errors and ensures the report directory exists.

4. **Environment Variables and MI Data:**
   - Configures and exports necessary environment variables.
   - Generates and sends MI data in JSON format with detailed logging of the data being sent.

## Reference

- [SonarQube Documentation](https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/)
