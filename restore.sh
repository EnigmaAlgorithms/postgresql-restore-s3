#! /bin/sh

set -e
set -o pipefail

>&2 echo "-----"

if [ "${S3_ACCESS_KEY_ID}" = "**None**" -a "${S3_ACCESS_KEY_ID_FILE}" = "**None**" ]; then
  echo "You need to set the S3_ACCESS_KEY_ID environment variable."
  exit 1
fi

if [ "${S3_SECRET_ACCESS_KEY}" = "**None**" -a "${S3_SECRET_ACCESS_KEY_FILE}" = "**None**" ]; then
  echo "You need to set the S3_SECRET_ACCESS_KEY environment variable."
  exit 1
fi

if [ "${S3_BUCKET}" = "**None**" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ "${POSTGRES_DB}" = "**None**" -a "${POSTGRES_DB_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DB environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" -a "${POSTGRES_USER_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" -a "${POSTGRES_PASSWORD_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

#Process vars
if [ "${POSTGRES_DB_FILE}" = "**None**" ]; then
  POSTGRES_DB=$(echo "${POSTGRES_DB}" | tr , " ")
elif [ -r "${POSTGRES_DB_FILE}" ]; then
  POSTGRES_DB=$(cat "${POSTGRES_DB_FILE}")
else
  echo "Missing POSTGRES_DB_FILE file."
  exit 1
fi
if [ "${POSTGRES_USER_FILE}" = "**None**" ]; then
  export PGUSER="${POSTGRES_USER}"
elif [ -r "${POSTGRES_USER_FILE}" ]; then
  export PGUSER=$(cat "${POSTGRES_USER_FILE}")
else
  echo "Missing POSTGRES_USER_FILE file."
  exit 1
fi
if [ "${POSTGRES_PASSWORD_FILE}" = "**None**" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
elif [ -r "${POSTGRES_PASSWORD_FILE}" ]; then
  export PGPASSWORD=$(cat "${POSTGRES_PASSWORD_FILE}")
else
  echo "Missing POSTGRES_PASSWORD_FILE file."
  exit 1
fi
if [ "${S3_ACCESS_KEY_ID_FILE}" = "**None**" ]; then
  export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}"
elif [ -r "${S3_ACCESS_KEY_ID_FILE}" ]; then
  export AWS_ACCESS_KEY_ID=$(cat "${S3_ACCESS_KEY_ID_FILE}")
else
  echo "Missing S3_ACCESS_KEY_ID_FILE file."
  exit 1
fi
if [ "${S3_SECRET_ACCESS_KEY_FILE}" = "**None**" ]; then
  export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}"
elif [ -r "${S3_SECRET_ACCESS_KEY_FILE}" ]; then
  export AWS_SECRET_ACCESS_KEY=$(cat "${S3_SECRET_ACCESS_KEY_FILE}")
else
  echo "Missing S3_SECRET_ACCESS_KEY_FILE file."
  exit 1
fi
if [ "${ENCRYPTION_PASSWORD_FILE}" = "**None**" ]; then
  ENCRYPTION_PASSWORD="${ENCRYPTION_PASSWORD}"
elif [ -r "${ENCRYPTION_PASSWORD_FILE}" ]; then
  ENCRYPTION_PASSWORD=$(cat "${ENCRYPTION_PASSWORD_FILE}")
else
  echo "Missing ENCRYPTION_PASSWORD_FILE file."
  exit 1
fi
export AWS_DEFAULT_REGION=$S3_REGION

POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $PGUSER"

echo "Finding latest backup"

if [ "${ENCRYPTION_PASSWORD}" != "**None**" ]; then
  LATEST_BACKUP=$(aws s3 ls s3://$S3_BUCKET/$S3_PREFIX/ | sort | grep .enc | tail -n 1 | awk '{ print $4 }')
  echo "Fetching ${LATEST_BACKUP} from S3"
  aws s3 cp s3://$S3_BUCKET/$S3_PREFIX/${LATEST_BACKUP} dump.sql.gz.enc
  openssl aes-256-cbc -d -in dump.sql.gz.enc -out dump.sql.gz -k $ENCRYPTION_PASSWORD
else
  LATEST_BACKUP=$(aws s3 ls s3://$S3_BUCKET/$S3_PREFIX/ | sort | tail -n 1 | awk '{ print $4 }')
  echo "Fetching ${LATEST_BACKUP} from S3"
  aws s3 cp s3://$S3_BUCKET/$S3_PREFIX/${LATEST_BACKUP} dump.sql.gz
fi

gzip -d dump.sql.gz

if [ "${DROP_PUBLIC}" == "yes" ]; then
	echo "Recreating the public schema"
	psql $POSTGRES_HOST_OPTS -d $POSTGRES_DB -c "drop schema public cascade; create schema public;"
fi

echo "Restoring ${LATEST_BACKUP}"

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DB < dump.sql

echo "Restore complete"

