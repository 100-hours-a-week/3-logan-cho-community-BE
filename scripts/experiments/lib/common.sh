#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TERRAFORM_EXPERIMENT_DIR="${PROJECT_ROOT}/infra/terraform/envs/experiment"

: "${EXPERIMENT_AWS_PROFILE:=default}"
: "${EXPERIMENT_AWS_REGION:=ap-northeast-2}"

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
export AWS_SDK_LOAD_CONFIG=1
export AWS_PROFILE="${EXPERIMENT_AWS_PROFILE}"
export AWS_DEFAULT_PROFILE="${EXPERIMENT_AWS_PROFILE}"
export AWS_REGION="${EXPERIMENT_AWS_REGION}"
export AWS_DEFAULT_REGION="${EXPERIMENT_AWS_REGION}"
export AWS_PROFILE
export AWS_REGION

: "${EXPERIMENT_SSH_USER:=ec2-user}"
: "${EXPERIMENT_SSH_KEY_PATH:=${HOME}/.ssh/experiment_image_pipeline_key}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "${cmd}" >&2
    exit 1
  fi
}

tf_output() {
  local key="$1"
  terraform -chdir="${TERRAFORM_EXPERIMENT_DIR}" output -raw "${key}"
}

app_instance_id() {
  tf_output app_instance_id
}

k6_instance_id() {
  tf_output k6_instance_id
}

app_public_ip() {
  tf_output app_public_ip
}

k6_public_ip() {
  tf_output k6_public_ip
}

app_private_ip() {
  aws ec2 describe-instances \
    --instance-ids "$(app_instance_id)" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text
}

k6_private_ip() {
  aws ec2 describe-instances \
    --instance-ids "$(k6_instance_id)" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text
}

bucket_name() {
  tf_output s3_bucket_name
}

ssm_send() {
  local instance_id="$1"
  local comment="$2"
  local commands_json="$3"

  aws ssm send-command \
    --instance-ids "${instance_id}" \
    --document-name AWS-RunShellScript \
    --comment "${comment}" \
    --parameters "commands=${commands_json}" \
    --query 'Command.CommandId' \
    --output text
}

ssm_wait() {
  local command_id="$1"
  local deadline=$((SECONDS + 1800))

  while true; do
    local status
    status="$(aws ssm list-command-invocations \
      --command-id "${command_id}" \
      --details \
      --query 'CommandInvocations[0].Status' \
      --output text)"

    case "${status}" in
      Success|Cancelled|Failed|TimedOut|Cancelling)
        printf '%s' "${status}"
        return 0
        ;;
    esac

    if (( SECONDS > deadline )); then
      printf 'TimedOut'
      return 0
    fi

    sleep 5
  done
}

ssm_output() {
  local command_id="$1"
  aws ssm list-command-invocations \
    --command-id "${command_id}" \
    --details \
    --output json
}

ensure_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf 'required file not found: %s\n' "${path}" >&2
    exit 1
  fi
}

ssh_key_path() {
  printf '%s' "${EXPERIMENT_SSH_KEY_PATH}"
}

ssh_user() {
  printf '%s' "${EXPERIMENT_SSH_USER}"
}

ssh_opts() {
  printf '%s' "-i $(ssh_key_path) -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts -o ConnectTimeout=10"
}

app_ssh_host() {
  app_public_ip
}

k6_ssh_host() {
  k6_public_ip
}

ssh_run() {
  local host="$1"
  shift
  ensure_file "$(ssh_key_path)"
  ssh -i "$(ssh_key_path)" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
    -o ConnectTimeout=10 \
    "$(ssh_user)@${host}" "$@"
}

scp_to() {
  local source_path="$1"
  local host="$2"
  local dest_path="$3"
  ensure_file "$(ssh_key_path)"
  scp -i "$(ssh_key_path)" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile="${HOME}/.ssh/known_hosts" \
    -o ConnectTimeout=10 \
    "${source_path}" "$(ssh_user)@${host}:${dest_path}"
}
