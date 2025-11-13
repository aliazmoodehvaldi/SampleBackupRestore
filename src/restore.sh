#!/bin/bash

base_path=$(echo $1 | sed 's/.*=//')
. "$base_path/utils/init.sh" $base_path

FORCE_RESTORE=${FORCE_RESTORE:-false}

LATEST_FILE=$(aws s3api list-objects-v2 \
  --endpoint-url "$ENDPOINT_URL" \
  --bucket "$S3_BUCKET" \
  --prefix "$PROJECT_NAME" \
  --query 'Contents[?starts_with(Key, `'"$PROJECT_NAME"'`)] | sort_by(@, &LastModified)[-1].Key' \
  --output text)

if [[ "$LATEST_FILE" == "None" || -z "$LATEST_FILE" ]]; then
  echo "❌ No file starting with '$PROJECT_NAME' found in bucket '$S3_BUCKET'."
  exit 1
fi

echo "📦 Downloading latest backup: $LATEST_FILE"
aws s3 cp "s3://$S3_BUCKET/$LATEST_FILE" ./backup.tar.gz --endpoint-url "$ENDPOINT_URL"
LATEST_FILE="./backup.tar.gz"

if [[ $? -ne 0 ]]; then
  echo "❌ Failed to download the file."
  exit 2
fi

echo "✅ Backup downloaded successfully."

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