# BP-SONAR-SCANNER-STEP
A BP step to perform SonarQube scanning and optionally send the results to an MI server.


## Latest Changes
- Updated sonar to v7.0.2
- Fixed duplicate log prints
- Removed MI data push

To use MI code, checkout to this branch's commit - `6a8b3dd376f7435158122046c5cf28d971075e7a`

## Setup

### Clone the Repository
```bash
git clone https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-SONAR-SCANNER-STEP.git
cd BP-SONAR-SCANNER-STEP
```

### Build the Docker Image
Ensure you are using the correct branch for the base shell steps:

```bash
git submodule init
git submodule update
docker build -t registry.buildpiper.in/okts/sonar-scan:tag .
```
**Note:** Use the `v0.7` branch for `BP-BASE-SHELL-STEPS`.

### Local Testing

If you want to test the SonarQube Scanner CLI:

```bash
sonar-scanner -Dsonar.login=<token> -Dsonar.host.url=https://sonarcloud.io/ -Dsonar.projectKey=<project-key> -Dsonar.organization=<org-key> -Dsonar.java.binaries=target/classes
```

If you want to pass all arguments at runtime:

```bash
docker run -it --rm \
  -v $PWD:/src \
  -e WORKSPACE=/ \
  -e CODEBASE_DIR=src \
  -e APPLICATION_NAME=<application_name> \
  -e ORGANIZATION=<organization_name> \
  -e SOURCE_KEY=<source_key> \
  -e REPORT_FILE_PATH=<report_file_path> \
  -e MI_SERVER_ADDRESS=<mi_server_address> \
  registry.buildpiper.in/okts/sonar-scan:tag \
  "-Dsonar.login=<token> -Dsonar.host.url=https://sonarcloud.io/ -Dsonar.projectKey=<project-key> -Dsonar.organization=<org-key> -Dsonar.java.binaries=target/classes"
```

Preferred one (if using a `sonar.properties` file):

```bash
docker run -it --rm \
  -v $PWD:/src \
  -e WORKSPACE=/ \
  -e CODEBASE_DIR=src \
  registry.buildpiper.in/okts/sonar-scan:tag \
  "-Dsonar.login=<token> -Dproject.settings=sonar.properties"
```

### Default Behavior and Customization

- **JAVA_BINARIES**: By default, the `JAVA_BINARIES` environment variable is set to `.` (the current directory). This can be overridden if your compiled Java classes are located in a different directory.

  - **Suggestion**: If you know where your Java classes are located, set the `JAVA_BINARIES` environment variable to that directory path.

  Example:
  ```bash
  export JAVA_BINARIES=target/classes
  ```

## Required Environment Variables

The script requires several environment variables to be set:

- `SONAR_TOKEN`: The token used to authenticate with SonarQube.
- `SONAR_URL`: The URL of the SonarQube server.
- `APPLICATION_NAME`: The name of the application being scanned.
- `ORGANIZATION`: The organization name.
- `SOURCE_KEY`: The source key used in the MI server.
- `REPORT_FILE_PATH`: The path where the SonarQube report is stored.
- `MI_SERVER_ADDRESS`: The address of the MI server where the report will be sent.

If any of these variables are missing, the script will exit with an error.

## Workflow Overview

1. **SonarQube Scan**: The script scans the codebase using the SonarQube scanner.
2. **Fetch Metrics**: After the scan, the script attempts to fetch metrics from the SonarQube server.
3. **Generate and Send Report**: The script generates a summary of the scan results and optionally sends this report to the MI server.

### Conditional Handling

- **Successful Scan and Report Sending**: If both the scan and the report sending are successful, a success message is logged and output is generated.
- **Successful Scan but Failed Report Sending**: If the scan succeeds but the report sending fails, a warning is logged, and the process continues.
- **Scan Failure**: If the scan fails, an error message is logged and the script may exit based on the configuration.

## Reference

- For more information on using the SonarQube Scanner, refer to the [SonarQube Documentation](https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/).
