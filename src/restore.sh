#!/bin/bash

base_path=$(echo $1 | sed 's/.*=//')
. "$base_path/utils/init.sh" $base_path

FORCE_RESTORE=${FORCE_RESTORE:-false}

download_latest_backup () {
    local profile=$1
    local endpoint=$2
    local bucket=$3

    echo "📦 Checking bucket '$bucket' with profile '$profile'..."

    LATEST_FILE=$(timeout 15 aws s3api list-objects-v2 \
      --endpoint-url "$endpoint" \
      --bucket "$bucket" \
      --prefix "$PROJECT_NAME" \
      --profile "$profile" \
      --query 'Contents[?starts_with(Key, `'"$PROJECT_NAME"'`)] | sort_by(@, &LastModified)[-1].Key' \
      --output text 2>/dev/null)

    echo $LATEST_FILE
    if [[ $? -ne 0 ]]; then
        echo "⚠️ Could not connect to bucket '$bucket' with profile '$profile'. Skipping."
        return 1
    fi

    if [[ -z "$LATEST_FILE" || "$LATEST_FILE" == "None" ]]; then
        echo "⚠️ No backup file found in bucket '$bucket'. Skipping."
        return 1
    fi

    echo "📦 Downloading latest backup: $LATEST_FILE from bucket '$bucket'"
    timeout 30 aws s3 cp "s3://$bucket/$LATEST_FILE" ./backup.tar.gz --endpoint-url "$endpoint" --profile "$profile"
    if [[ $? -ne 0 ]]; then
        echo "⚠️ Failed to download backup from profile '$profile'. Trying next profile..."
        return 1
    fi

    LATEST_FILE="./backup.tar.gz"
    return 0
}

# --- Multi-Account handling ---
if [[ "$MULTI_ACCOUNT" == "true" ]]; then
    profiles=$(aws configure list-profiles)
    backup_downloaded=false

    for profile in $profiles; do
        upper_profile=$(echo "$profile" | tr '[:lower:]' '[:upper:]')
        endpoint_var="ENDPOINT_URL_${upper_profile}"
        bucket_var="S3_BUCKET_${upper_profile}"

        endpoint="${!endpoint_var}"
        bucket="${!bucket_var}"

        if [[ -z "$endpoint" || -z "$bucket" ]]; then
            echo "⚠️ Profile '$profile' missing endpoint or bucket. Skipping."
            continue
        fi

        download_latest_backup "$profile" "$endpoint" "$bucket"
        if [[ $? -eq 0 ]]; then
            echo "✅ Backup downloaded successfully from profile '$profile'."
            backup_downloaded=true
            break
        fi
    done

    if [[ "$backup_downloaded" == "false" ]]; then
        echo "❌ No backup could be downloaded from any profile."
        exit 1
    fi
else
    if [[ -z "$ENDPOINT_URL" || -z "$S3_BUCKET" ]]; then
        echo "❌ ENDPOINT_URL or S3_BUCKET not defined."
        exit 1
    fi

    download_latest_backup "default" "$ENDPOINT_URL" "$S3_BUCKET"
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to download backup."
        exit 1
    fi
fi

echo "✅ Backup ready. Proceeding with restore..."

# Stop containers
sudo docker stop $TARGET_CONTAINER
if [[ -n "$SECOND_CONTAINER" ]]; then
  sudo docker stop $SECOND_CONTAINER
fi

echo "🔄 Extracting backup..."
sudo tar -xzf "$LATEST_FILE"

echo "🧹 Replacing target path..."
sudo rm -rf "$TARGET_PATH"
sudo mkdir -p "$TARGET_PATH"
sudo cp -R ".$TARGET_PATH" "$(dirname "$TARGET_PATH")"
sudo rm -rf "./$(echo "$TARGET_PATH" | cut -d'/' -f2)"
sudo rm -f "$LATEST_FILE"

ERROR_FOUND=false

if [[ "$FORCE_RESTORE" != "true" ]]; then
  echo "⏳ Monitoring MongoDB logs..."
  MAX_WAIT=120
  COUNTER=0

  while [[ $COUNTER -lt $MAX_WAIT ]]; do
    LOGS=$(sudo docker logs $TARGET_CONTAINER 2>&1 | tail -n 50)

    if echo "$LOGS" | grep -q "50883"; then
      echo "⚠️ MongoDB fatal assertion 50883 detected."
      ERROR_FOUND=true
      break
    fi

    if echo "$LOGS" | grep -q "Waiting for connections"; then
      echo "✅ MongoDB started successfully."
      break
    fi

    sleep 2
    ((COUNTER+=2))
  done
else
  echo "⚡ FORCE_RESTORE=true, skipping MongoDB log monitoring."
  ERROR_FOUND=true
fi


if $ERROR_FOUND || [[ "$FORCE_RESTORE" == "true" ]]; then
  echo "⚠️ Starting recovery mode..."

  DUMP_FILE=$(find "$TARGET_PATH" -type f -name "*.dump" | head -n 1)

  if [[ -z "$DUMP_FILE" ]]; then
    echo "❌ No dump file found in $TARGET_PATH."
    exit 3
  fi

  DUMP_NAME=$(basename "$DUMP_FILE")
  echo "📄 Found dump file: $DUMP_NAME"

  echo "🧹 Cleaning target path except dump file..."
  find "$TARGET_PATH" -mindepth 1 -not -name "$DUMP_NAME" -exec sudo rm -rf {} +

  echo "🔁 Starting Mongo container..."
  sudo docker start $TARGET_CONTAINER

  sleep 60
  
  echo "⏳ Waiting for MongoDB to be ready..."
  until sudo docker logs $TARGET_CONTAINER 2>&1 | grep -q "Waiting for connections"; do
    sleep 2
  done

  echo "♻️ Restoring database from /data/db/$DUMP_NAME ..."
  sudo docker exec $TARGET_CONTAINER mongorestore --verbose \
    --archive=/data/db/$DUMP_NAME \
    --authenticationDatabase admin -u $MONGO_USERNAME -p $MONGO_PASSWORD

  if [[ $? -eq 0 ]]; then
    echo "✅ Database restored successfully."
  else
    echo "❌ Database restore failed."
    exit 4
  fi
else
  echo "✅ No fatal MongoDB error detected. No restore needed."
fi

echo "🚀 Starting containers..."
sudo docker start $TARGET_CONTAINER
if [[ -n "$SECOND_CONTAINER" ]]; then
  sudo docker start $SECOND_CONTAINER
fi