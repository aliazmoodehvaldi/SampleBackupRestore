#!/bin/bash

. "$1/utils/utils.sh"

# Check exist aws tools
if ! has_exist_command "aws"; then
    echo "${red}Error: aws does not found"
    exit 1
fi

# Check if .env file exists
if [ -f "$1/.env" ]; then
    # Load variables from .env file
    . "$1/.env"
else
    echo "${red}Error: .env file not found."
    exit 1
fi

# Define the list of common environment variable names
env_variables=(
    "SECOND_CONTAINER"
    "TARGET_CONTAINER"
    "MONGO_USERNAME"
    "MONGO_PASSWORD"
    "FORCE_RESTORE"
    "PROJECT_NAME"
    "SCRIPT_PATH"
    "TARGET_PATH"
)

# Check common env variables
for var_name in "${env_variables[@]}"; do
    if [ -z "${!var_name}" ]; then
        echo "${yellow}Warning: $var_name is not set"
    fi
done

# --- Check AWS related env ---
if [[ "$MULTI_ACCOUNT" == "true" ]]; then
    profiles=$(aws configure list-profiles)
    missing_env=0

    for profile in $profiles; do
        upper_profile=$(echo "$profile" | tr '[:lower:]' '[:upper:]')

        endpoint_var="ENDPOINT_URL_${upper_profile}"
        bucket_var="S3_BUCKET_${upper_profile}"

        if [ -z "${!endpoint_var}" ]; then
            echo "${red}Error: Endpoint for profile '$profile' not set. Expected env: $endpoint_var"
            missing_env=1
        fi

        if [ -z "${!bucket_var}" ]; then
            echo "${red}Error: S3 bucket for profile '$profile' not set. Expected env: $bucket_var"
            missing_env=1
        fi
    done

    if [[ $missing_env -eq 1 ]]; then
        echo "${red}Please set all required ENDPOINT_URL_<PROFILE> and S3_BUCKET_<PROFILE> variables in your .env file."
        exit 1
    fi
else
    if [ -z "$ENDPOINT_URL" ]; then
        echo "${red}Error: ENDPOINT_URL is not set for single account."
        exit 1
    fi
    if [ -z "$S3_BUCKET" ]; then
        echo "${red}Error: S3_BUCKET is not set for single account."
        exit 1
    fi
fi