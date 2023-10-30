#!/bin/bash

apt-get update -y
apt install curl dnsutils jq -y

curl https://dl.min.io/client/mc/release/linux-amd64/mc --create-dirs -o /usr/local/bin/mc
chmod +x /usr/local/bin/mc
ls -al /usr/local/bin

mc alias set "$DEPLOYMENT_NAME" "$DEPLOYMENT_URL" "$ADMIN_USERNAME" "$ADMIN_PASSWORD" --insecure
echo $(mc alias list --json)
mc mb "$DEPLOYMENT_NAME/$NEW_BUCKET_NAME" --ignore-existing --region "$DEPLOYMENT_REGION" --insecure

USER=$(mc admin user info "$DEPLOYMENT_NAME" "$NEW_USER_NAME" --json --insecure)
echo "USER:$USER"
USER_STATUS=$(echo $USER | jq ' .status')
echo "USER_STATUS:$USER_STATUS"
if [[ $USER_STATUS == "\"error\"" ]] 
then
  USER_STATUS_ERROR_CODE=$(echo $USER | jq ' .error.cause.error.Code')
  echo "USER_STATUS_ERROR_CODE:$USER_STATUS_ERROR_CODE"
  if [[ $USER_STATUS_ERROR_CODE == "\"XMinioAdminNoSuchUser\"" ]] 
  then
    echo "Adding user:$NEW_USER_NAME"
    mc admin user add "$DEPLOYMENT_NAME" "$NEW_USER_NAME" "$NEW_USER_PASSWORD"
    echo "Added user:$NEW_USER_NAME"
  fi
else
  echo "User:$NEW_USER_NAME exists."
fi

SERVICE_ACCOUNT=$(mc admin user svcacct info "$DEPLOYMENT_NAME" "$NEW_USER_SERVICE_ACCOUNT_ACCESSKEY" --json --insecure)
echo "SERVICE_ACCOUNT:$SERVICE_ACCOUNT"
SERVICE_ACCOUNT_STATUS=$(echo $SERVICE_ACCOUNT | jq ' .status')
echo "SERVICE_ACCOUNT_STATUS:$SERVICE_ACCOUNT_STATUS"
if [[ $SERVICE_ACCOUNT_STATUS == "\"error\"" ]] 
then
  SERVICE_ACCOUNT_STATUS_ERROR_CODE=$(echo $SERVICE_ACCOUNT | jq ' .error.cause.error.Code')
  echo "SERVICE_ACCOUNT_STATUS_ERROR_CODE:$SERVICE_ACCOUNT_STATUS_ERROR_CODE"
  if [[ $SERVICE_ACCOUNT_STATUS_ERROR_CODE == "\"XMinioInvalidIAMCredentials\"" ]] 
  then
    echo "Adding service account:$NEW_USER_SERVICE_ACCOUNT_ACCESSKEY to user:$NEW_USER_NAME"
    mc admin user svcacct add --access-key "$NEW_USER_SERVICE_ACCOUNT_ACCESSKEY" --secret-key "$NEW_USER_SERVICE_ACCOUNT_SECRETKEY" "$DEPLOYMENT_NAME" "$NEW_USER_NAME" 
    echo "Added service account:$NEW_USER_SERVICE_ACCOUNT_ACCESSKEY to user:$NEW_USER_NAME"
  fi
else
  echo "Service account:$NEW_USER_SERVICE_ACCOUNT_ACCESSKEY exists."
fi

GROUP=$(mc admin group info "$DEPLOYMENT_NAME" "$NEW_GROUP_NAME" --json --insecure)
echo "GROUP:$GROUP"
GROUP_STATUS=$(echo $GROUP | jq ' .status')
echo "GROUP_STATUS:$GROUP_STATUS"
if [[ $GROUP_STATUS == "\"error\"" ]] 
then
  GROUP_STATUS_ERROR_CODE=$(echo $GROUP | jq ' .error.cause.error.Code')
  echo "GROUP_STATUS_ERROR_CODE:$GROUP_STATUS_ERROR_CODE"
  if [[ $GROUP_STATUS_ERROR_CODE == "\"XMinioAdminNoSuchGroup\"" ]] 
  then
    echo "Adding group:$NEW_GROUP_NAME"
    mc admin group add "$DEPLOYMENT_NAME" "$NEW_GROUP_NAME" "$NEW_USER_NAME" --insecure
    echo "Added group:$NEW_GROUP_NAME"
  fi
else
  echo "Group:$NEW_GROUP_NAME exists."
fi

READ_POLICY_NAME="$NEW_POLICY_PREFIX.read"
READ_POLICY=$(mc admin policy info "$DEPLOYMENT_NAME" "$READ_POLICY_NAME" --json --insecure)
echo "READ_POLICY:$READ_POLICY"
READ_POLICY_STATUS=$(echo $READ_POLICY | jq ' .status')
echo "READ_POLICY_STATUS:$READ_POLICY_STATUS"
if [[ $READ_POLICY_STATUS == "\"error\"" ]] 
then
  READ_POLICY_ERROR_CODE=$(echo $READ_POLICY | jq ' .error.cause.error.Code')
  echo "READ_POLICY_ERROR_CODE:$READ_POLICY_ERROR_CODE"
  if [[ $READ_POLICY_ERROR_CODE == "\"XMinioAdminNoSuchPolicy\"" ]]
  then
    READ_POLICY_FILE_PATH="/tmp/$READ_POLICY_NAME.json"
    echo "Creating policy file:$READ_POLICY_NAME.json"
    cat > "$READ_POLICY_FILE_PATH" <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:ListBucketVersions"
          ],
          "Resource": [
            "arn:aws:s3:::${NEW_BUCKET_NAME}"
          ]
        },
        {
          "Effect": "Allow",
          "Action": [
            "s3:GetBucketObjectLockConfiguration",
            "s3:GetObject",
            "s3:GetObjectTagging",
            "s3:GetObjectVersionTagging",
            "s3:GetObjectVersion",
            "s3:GetObjectRetention",
            "s3:GetObjectLegalHold",
            "s3:GetObjectVersionForReplication",
            "s3:ListMultipartUploadParts"
          ],
          "Resource": [
            "arn:aws:s3:::${NEW_BUCKET_NAME}/*"
          ]
        }
      ]
    }
EOF
    echo "Created policy file:$READ_POLICY_NAME.json"
  
    echo "Adding policy:$READ_POLICY_NAME"
    mc admin policy create "$DEPLOYMENT_NAME" "$READ_POLICY_NAME" "$READ_POLICY_FILE_PATH" --insecure
    echo "Added policy:$READ_POLICY_NAME"
  
    echo "Attaching policy:$READ_POLICY_NAME to user:$NEW_USER_NAME"
    mc admin policy attach "$DEPLOYMENT_NAME" "$READ_POLICY_NAME" --group "$NEW_GROUP_NAME" --insecure
    echo "Attached policy:$READ_POLICY_NAME to user:$NEW_USER_NAME"
  fi
else
  echo "Policy:$READ_POLICY_NAME exists."
fi

WRITE_POLICY_NAME="$NEW_POLICY_PREFIX.write"
WRITE_POLICY=$(mc admin policy info "$DEPLOYMENT_NAME" "$WRITE_POLICY_NAME" --json --insecure)
echo "WRITE_POLICY:$WRITE_POLICY"
WRITE_POLICY_STATUS=$(echo $WRITE_POLICY | jq ' .status')
echo "WRITE_POLICY_STATUS:$WRITE_POLICY_STATUS"
if [[ $WRITE_POLICY_STATUS == "\"error\"" ]]
then
  WRITE_POLICY_ERROR_CODE=$(echo $WRITE_POLICY | jq ' .error.cause.error.Code')
  if [[ $WRITE_POLICY_ERROR_CODE == "\"XMinioAdminNoSuchPolicy\"" ]]
  then
    WRITE_POLICY_FILE_PATH="/tmp/$WRITE_POLICY_NAME.json"
    echo "Creating policy file:$WRITE_POLICY_NAME.json"
    cat > "$WRITE_POLICY_FILE_PATH" <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:AbortMultipartUpload",
            "s3:PutObject",
            "s3:PutObjectTagging",
            "s3:PutObjectVersionTagging",
            "s3:PutObjectRetention",
            "s3:PutObjectLegalHold",
            "s3:PutBucketObjectLockConfiguration"
          ],
          "Resource": [
            "arn:aws:s3:::${NEW_BUCKET_NAME}/*"
          ]
        }
      ]
    }
EOF
    echo "Created policy file:$WRITE_POLICY_NAME.json"
  
    echo "Adding policy:$WRITE_POLICY_NAME"
    mc admin policy create "$DEPLOYMENT_NAME" "$WRITE_POLICY_NAME" "$WRITE_POLICY_FILE_PATH" --insecure
    echo "Added policy:$WRITE_POLICY_NAME"
  
    echo "Attaching policy:$WRITE_POLICY_NAME to user:$NEW_USER_NAME"
    mc admin policy attach "$DEPLOYMENT_NAME" "$WRITE_POLICY_NAME" --group "$NEW_GROUP_NAME" --insecure
    echo "Attached policy:$WRITE_POLICY_NAME to user:$NEW_USER_NAME"
  fi
else
  echo "Policy:$WRITE_POLICY_NAME exists."
fi


DELETE_POLICY_NAME="$NEW_POLICY_PREFIX.delete"
DELETE_POLICY=$(mc admin policy info "$DEPLOYMENT_NAME" "$DELETE_POLICY_NAME" --json --insecure)
echo "DELETE_POLICY:$DELETE_POLICY"
DELETE_POLICY_STATUS=$(echo $DELETE_POLICY | jq ' .status')
echo "DELETE_POLICY_STATUS:$DELETE_POLICY_STATUS"
if [[ $DELETE_POLICY_STATUS == "\"error\"" ]]
then
  DELETE_POLICY_ERROR_CODE=$(echo $DELETE_POLICY | jq ' .error.cause.error.Code')
  if [[ $DELETE_POLICY_ERROR_CODE == "\"XMinioAdminNoSuchPolicy\"" ]]
  then
    DELETE_POLICY_FILE_PATH="/tmp/$DELETE_POLICY_NAME.json"
    echo "Creating policy file:$DELETE_POLICY_NAME.json"
    cat > "$DELETE_POLICY_FILE_PATH" <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "s3:DeleteObject",
            "s3:DeleteObjectVersion",
            "s3:DeleteObjectVersionTagging"
          ],
          "Resource": [
            "arn:aws:s3:::${NEW_BUCKET_NAME}/*"
          ]
        }
      ]
    }
EOF
    echo "Created policy file:$DELETE_POLICY_NAME.json"
  
    echo "Adding policy:$DELETE_POLICY_NAME"
    mc admin policy create "$DEPLOYMENT_NAME" "$DELETE_POLICY_NAME" "$DELETE_POLICY_FILE_PATH" --insecure
    echo "Added policy:$DELETE_POLICY_NAME"
  
    echo "Attaching policy:$DELETE_POLICY_NAME to user:$NEW_USER_NAME"
    mc admin policy attach "$DEPLOYMENT_NAME" "$DELETE_POLICY_NAME" --group "$NEW_GROUP_NAME" --insecure
    echo "Attached policy:$DELETE_POLICY_NAME to user:$NEW_USER_NAME"
  fi
else
  echo "Policy:$DELETE_POLICY_NAME exists."
fi

exit 0