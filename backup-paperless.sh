#!/bin/bash

BASE_FOLDER=/root/paperless
CURRENT_DATE=`TZ=UTC date -I`

# Source environment variables 
# Paperless BUCKET_ID, BACKUP_APPLICATION_KEY_ID, BACKUP_ENCRYPTION_PASSPHRASE
source "$BASE_FOLDER/.keys"

# Paperless data directories
PAPERLESS_DOCKER_VOLUME=/var/lib/docker/volumes
PAPERLESS_MEDIA="$PAPERLESS_DOCKER_VOLUME/paperless_media"
PAPERLESS_DATA="$PAPERLESS_DOCKER_VOLUME/paperless_data"
PAPERLESS_PGDATA="$PAPERLESS_DOCKER_VOLUME/paperless_pgdata"

# Exclude the model from backups
MODEL_FILE="$PAPERLESS_DATA/_data/classification_model.pickle"

# Backup names
BACKUP_FILENAME="backup_$CURRENT_DATE.tar.gz"
SNAR_LOCATION="$BASE_FOLDER/data.sngz"

# Don't run a backup for the day if it already exists
if [ -f "$BACKUP_FILENAME" ]; then
    echo "$BACKUP_FILENAME exists. Exiting..."
    exit
fi

echo "Creating .tgz backup..."
tar --exclude $MODEL_FILE --create --gzip --listed-incremental=$SNAR_LOCATION --file=$BACKUP_FILENAME $PAPERLESS_MEDIA $PAPERLESS_DATA $PAPERLESS_PGDATA

echo "Encrypting backup with GPG..."
gpg --passphrase $BACKUP_ENCRYPTION_PASSPHRASE --batch --symmetric --cipher-algo aes256 $BACKUP_FILENAME

echo "Authorizing Backblaze access..."
AUTHORIZE_ACCOUNT_RESPONSE=$(curl https://api.backblazeb2.com/b2api/v2/b2_authorize_account -u "${PAPERLESS_BACKUP_APPLICATION_KEY_ID}:${PAPERLESS_BACKUP_APPLICATION_KEY}")

echo "Fetching Backblaze authorization token and API URL..."
AUTHORIZATION_TOKEN=$(echo "$AUTHORIZE_ACCOUNT_RESPONSE" |  jq -r '.authorizationToken') # -r to remove quotes
API_URL=$(echo "$AUTHORIZE_ACCOUNT_RESPONSE" |  jq '.apiUrl')

echo "Fetching upload URL and auth token..."
UPLOAD_RESPONSE=$(curl -H "Authorization: $AUTHORIZATION_TOKEN" -d '{"bucketId": "'"$PAPERLESS_BUCKET_ID"'"}' https://api005.backblazeb2.com/b2api/v2/b2_get_upload_url)

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.uploadUrl')
UPLOAD_AUTHORIZATION_TOKEN=$(echo "$UPLOAD_RESPONSE" | jq -r '.authorizationToken')

FILE_TO_UPLOAD="$BACKUP_FILENAME.gpg"
MIME_TYPE=application/gzip
SHA1_OF_FILE=$(openssl dgst -sha1 $FILE_TO_UPLOAD | awk '{print $2;}')

echo "Uploading $FILE_TO_UPLOAD to bucket with id $PAPERLESS_BUCKET_ID..."
curl \
    -H "Authorization: $UPLOAD_AUTHORIZATION_TOKEN" \
    -H "X-Bz-File-Name: $FILE_TO_UPLOAD" \
    -H "Content-Type: $MIME_TYPE" \
    -H "X-Bz-Content-Sha1: $SHA1_OF_FILE" \
    -H "X-Bz-Info-Author: unknown" \
    --data-binary "@$FILE_TO_UPLOAD" \
    $UPLOAD_URL

echo "Removing $BACKUP_FILENAME and $FILE_TO_UPLOAD..."
rm $BACKUP_FILENAME $FILE_TO_UPLOAD
