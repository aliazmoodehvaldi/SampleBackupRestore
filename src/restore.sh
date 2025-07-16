#!/bin/bash

base_path=$(echo $1 | sed 's/.*=//')

. "$base_path/utils/init.sh" $base_path

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

aws s3 cp "s3://$S3_BUCKET/$LATEST_FILE" ./backup.tar.gz --endpoint-url "$ENDPOINT_URL"

LATEST_FILE="./backup.tar.gz"

if [[ $? -eq 0 ]]; then
  sudo docker stop $TARGET_CONTAINER
  sudo tar -xzf "$LATEST_FILE"
  sudo rm -rf "$TARGET_PATH"
  sudo mkdir "$TARGET_PATH"
  sudo cp -R ".$TARGET_PATH" "$(dirname "$TARGET_PATH")"
  sudo rm -rf "./$(echo "$TARGET_PATH" | cut -d'/' -f2)"
  sudo rm -rf "$LATEST_FILE"
  sudo docker start $TARGET_CONTAINER
else
  echo "Failed to download the file."
  exit 2
fi
