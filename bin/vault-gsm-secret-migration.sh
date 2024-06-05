#! /bin/bash

# vault-gsm-secret-migration.sh
# script to pull out core SCP-specific secrets from vault and import them into Google Secret Manager (GSM)
# this will allow the use of ./rails_local_setup.rb with GSM
# require gcloud, vault, and jq to be installed and configured

function authenticate_vault {
  TOKEN_PATH="$1"
  vault login -method=github token=$(cat "$TOKEN_PATH")
}

function extract_secret_from_vault {
  SECRET_PATH="$1"
  vault read -field=data -format=json "$SECRET_PATH" | jq
}

function delete_gsm_secret {
  SECRET_NAME="$1"
  gcloud secrets delete "$SECRET_NAME" --quiet
}

function copy_secret_to_gsm {
  VAULT_PATH="$1"
  SECRET_NAME="$2"
  GOOGLE_PROJECT="$3"
  extract_secret_from_vault "$VAULT_PATH" | gcloud secrets create "$SECRET_NAME" --project="$GOOGLE_PROJECT" \
                                            --replication-policy=automatic --data-file=-
}

function exit_with_error {
  echo "### ERROR: $1 ###"
  exit 1
}

function main {
  GOOGLE_PROJECT=$(gcloud info --format="value(config.project)")
  BASEPATH="secret/kdux/scp/development/$(whoami)"
  ROLLBACK="false"
  while getopts "t:p:b:rh" OPTION; do
    case $OPTION in
      t)
        VAULT_TOKEN="$OPTARG"
        ;;
      p)
        GOOGLE_PROJECT="$OPTARG"
        echo "setting GOOGLE_PROJECT to $GOOGLE_PROJECT"
        ;;
      b)
        BASEPATH="$OPTARG"
        echo "setting BASEPATH to $BASEPATH"
        ;;
      r)
        ROLLBACK="true"
        ;;
      h)
        echo "$usage"
        exit 0
        ;;
      *)
        echo "unrecognized option"
        echo "$usage"
        exit 1
        ;;
    esac
  done

  # set up names/paths
  GSM_CONFIG_NAME="scp-config-json" # main configuration JSON
  GSM_DEFAULT_SA_NAME="default-sa-keyfile" # primary service account keyfile
  GSM_READONLY_SA_NAME="read-only-sa-keyfile" # read-only service account keyfile
  GSM_MONGO_USER_NAME="mongo-user" # MongoDB user credentials

  if [[ "$ROLLBACK" = "true" ]]; then
    echo "Rolling back GSM migration"
    echo -n "Deleting $GSM_CONFIG_NAME... "
    delete_gsm_secret "$GSM_CONFIG_NAME"
    echo -n "Deleting $GSM_DEFAULT_SA_NAME... "
    delete_gsm_secret "$GSM_DEFAULT_SA_NAME"
    echo -n "Deleting $GSM_READONLY_SA_NAME... "
    delete_gsm_secret "$GSM_READONLY_SA_NAME"
    echo -n "Deleting $GSM_MONGO_USER_NAME... "
    delete_gsm_secret "$GSM_MONGO_USER_NAME"
    echo "Rollback complete!"
    exit 0
  fi

  # vault paths
  CONFIG_PATH="$BASEPATH/scp_config.json"
  DEFAULT_KEYFILE="$BASEPATH/scp_service_account.json"
  READONLY_KEYFILE="$BASEPATH/read_only_service_account.json"
  MONGO_CREDS="$BASEPATH/mongo/user"

  authenticate_vault "$VAULT_TOKEN" || exit_with_error "cannot authenticate into vault"

  echo -n "Copying $CONFIG_PATH from vault... "
  copy_secret_to_gsm "$CONFIG_PATH" "$GSM_CONFIG_NAME" "$GOOGLE_PROJECT" || exit_with_error "failed to copy $CONFIG_PATH"
  echo -n "Copying $DEFAULT_KEYFILE from vault... "
  copy_secret_to_gsm "$DEFAULT_KEYFILE" "$GSM_DEFAULT_SA_NAME" "$GOOGLE_PROJECT" || exit_with_error "failed to copy $DEFAULT_KEYFILE"
  echo -n "Copying $READONLY_KEYFILE from vault... "
  copy_secret_to_gsm "$READONLY_KEYFILE" "$GSM_READONLY_SA_NAME" "$GOOGLE_PROJECT" || exit_with_error "failed to copy $READONLY_KEYFILE"
  echo -n "Copying $MONGO_CREDS from vault... "
  copy_secret_to_gsm "$MONGO_CREDS" "$GSM_MONGO_USER_NAME" "$GOOGLE_PROJECT" || exit_with_error "failed to copy $MONGO_CREDS"

  echo "All required secrets migrated to GSM"
  exit 0
}

usage=$(
cat <<EOF
USAGE:
  $(basename $0) -t VAULT_TOKEN [<options>]

  -t VAULT_TOKEN  set the path to token used to authenticate into vault (no default)

  [OPTIONS]
  -p PROJECT      set the GCP project in which to create secrets (defaults to '$(gcloud info --format="value(config.project)")')
  -b BASEPATH     set the base vault path for retrieving secrets (defaults to 'secret/kdux/scp/development/$(whoami)')
  -r              roll back migration and delete SCP secrets in GSM
  -h              print this message
EOF
)

main "$@"
