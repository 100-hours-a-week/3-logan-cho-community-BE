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

optional_tf_output() {
  local key="$1"
  terraform -chdir="${TERRAFORM_EXPERIMENT_DIR}" output -raw "${key}" 2>/dev/null || true
}

app_instance_id() {
  tf_output app_instance_id
}

app_asg_name() {
  optional_tf_output app_asg_name
}

k6_instance_id() {
  tf_output k6_instance_id
}

app_public_ip() {
  tf_output app_public_ip
}

app_alb_dns_name() {
  optional_tf_output app_alb_dns_name
}

k6_public_ip() {
  tf_output k6_public_ip
}

db_instance_id() {
  optional_tf_output db_instance_id
}

db_public_ip() {
  optional_tf_output db_public_ip
}

db_private_ip() {
  optional_tf_output db_private_ip
}

app_base_url() {
  local alb_dns
  alb_dns="$(app_alb_dns_name)"
  if [[ -n "${alb_dns}" && "${alb_dns}" != "null" ]]; then
    printf 'http://%s:8080' "${alb_dns}"
    return 0
  fi
  printf 'http://%s:8080' "$(app_public_ip)"
}

app_instance_ids() {
  local asg
  asg="$(app_asg_name)"
  if [[ -n "${asg}" && "${asg}" != "null" ]]; then
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "${asg}" \
      --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
      --output text | tr '\t' '\n' | sed '/^$/d'
    return 0
  fi
  app_instance_id
}

app_public_ips() {
  local ids
  ids="$(app_instance_ids | tr '\n' ' ')"
  if [[ -z "${ids// }" ]]; then
    return 0
  fi
  aws ec2 describe-instances \
    --instance-ids ${ids} \
    --query 'Reservations[].Instances[].PublicIpAddress' \
    --output text | tr '\t' '\n' | sed '/^$/d'
}

app_private_ip() {
  if [[ -n "$(app_asg_name)" && "$(app_asg_name)" != "null" ]]; then
    local first_id
    first_id="$(app_instance_ids | head -n 1)"
    aws ec2 describe-instances \
      --instance-ids "${first_id}" \
      --query 'Reservations[0].Instances[0].PrivateIpAddress' \
      --output text
    return 0
  fi
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
  app_public_ips | head -n 1
}

db_ssh_host() {
  db_public_ip
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

upload_to_s3_via_instance_role() {
  local source_path="$1"
  local host="$2"
  local s3_uri="$3"
  local remote_path="/tmp/$(basename "${source_path}")"

  ensure_file "${source_path}"
  scp_to "${source_path}" "${host}" "${remote_path}"
  ssh_run "${host}" "aws s3 cp '${remote_path}' '${s3_uri}' >/dev/null"
}

callback_secret_file() {
  printf '%s' "${HOME}/.cache/image-pipeline-experiments/callback-secret"
}

ensure_callback_secret() {
  local path
  path="$(callback_secret_file)"
  mkdir -p "$(dirname "${path}")"

  if [[ -n "${EXPERIMENT_IMAGE_CALLBACK_SECRET:-}" ]]; then
    printf '%s\n' "${EXPERIMENT_IMAGE_CALLBACK_SECRET}" > "${path}"
    chmod 600 "${path}"
  fi

  if [[ ! -f "${path}" ]]; then
    python3 - <<'PY' > "${path}"
import secrets
print(secrets.token_hex(24))
PY
    chmod 600 "${path}"
  fi

  cat "${path}"
}
