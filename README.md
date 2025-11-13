# Backup restoring Mechanism Implementation Guide

This guide outlines the steps to implement a backup restoring mechanism utilizing AWS S3 storage, cron jobs, and shell scripts.

## Step 1: Install AWS SDK

```shell
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt-get install unzip
unzip awscliv2.zip
sudo ./aws/install
```

## Step 2: AWS Configuration

```shell
sudo aws configure
```

Configure your access key ID, secret access key, and region. skip the last option if unsure.

## Step 3: Install Cron

```shell
sudo apt-get install cron
```

## Step 4: Launch Scripts

1. Create a new folder: `mkdir /home/restore`
2. Download scripts and copy the zip file to `/home/restore`.
3. Create a .env file in `/home/restore` and set the following environment variables:
4. Grant execute access to scripts: `sudo chmod +x /home/restore/*.sh`

| KEY                  | Type   | Required | Description                                  |
|----------------------|--------|----------|----------------------------------------------|
| S3_BUCKET            | String | true     | S3 bucket name                               |
| ENDPOINT_URL         | String | true     | S3 endpoint url                              |
| SCRIPT_PATH          | String | true     | Address of root scripts of the project       |
| TARGET_PATH          | String | true     | The address of the restore path              |
| PROJECT_NAME         | String | false    | Choosing project name for final restore file |
| MONGO_USERNAME       | String | false    | MongoDB username                             |
| MONGO_PASSWORD       | String | false    | MongoDB password                             |
| FORCE_RESTORE        | Boolean| false    | Force Restore data with MongoRestore         |
| TARGET_CONTAINER     | String | true     | Target docker container                      |
| SECOND_CONTAINER     | String | false    | Second docker container                      |

### Example

```text
S3_BUCKET=bucket_test
ENDPOINT_URL=https://domain.com
SCRIPT_PATH=/home/restore
TARGET_PATH=/home/app
PROJECT_NAME=PROJECT_NAME
TARGET_CONTAINER=TARGET_CONTAINER
```

## Step 5: Cron Job Configuration

```shell
sudo crontab -e
```

Choose your preferred editor and add the following commands:

```shell
0 1 * * * /home/restore/restore.sh --path=/home/restore >> /home/restore/restore-error.log 2>&1
```
