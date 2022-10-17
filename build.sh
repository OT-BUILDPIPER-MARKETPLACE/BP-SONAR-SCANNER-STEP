#!/bin/bash
source functions.sh

logInfoMessage "I'll scan the code available at [$WORKSPACE] and have mounted at [$CODEBASE_DIR]"
sleep  $SLEEP_DURATION
cd  $WORKSPACE/${CODEBASE_DIR}

logInfoMessage "I've recieved below arguments [$@]"

sonar-scanner $@