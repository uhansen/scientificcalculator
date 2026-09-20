#!/usr/bin/env bash

info() { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
die()  { echo "  ✗ $*" >&2; exit 1; }

require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

tf() {
  mise exec terraform@1.16.3 -- terraform "$@"
}

resolve_registry_token() {
  local token="${GHCR_TOKEN:-${CR_PAT:-${GITHUB_TOKEN:-}}}"
  if [[ -n "${token}" ]]; then
    printf '%s\n' "${token}"
    return 0
  fi

  gh auth status --hostname github.com >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"
  gh auth token
}

detect_public_cidr() {
  local ip
  ip="$(curl -fsS https://api.ipify.org 2>/dev/null || curl -fsS https://ifconfig.me 2>/dev/null || true)"
  [[ -n "${ip}" ]] || die "Could not determine the current public IPv4 address"
  printf '%s/32\n' "${ip}"
}

slugify_alnum() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
}

write_file() {
  local path="${1}"
  shift
  cat >"${path}" <<EOF
$*
EOF
}

run_tf_plan_apply() {
  local dir="${1}" backend_args=("${@:2}") plan_file
  plan_file="${dir}/terraform.tfplan"

  (
    cd "${dir}"
    tf init -reconfigure "${backend_args[@]}"
    tf plan -out="${plan_file}"
    if [[ "${TF_PLAN_ONLY:-false}" == "true" ]]; then
      ok "Terraform plan created at ${plan_file}"
      return 0
    fi

    if [[ "${TF_AUTO_APPROVE:-true}" == "true" ]]; then
      tf apply -auto-approve "${plan_file}"
    else
      tf apply "${plan_file}"
    fi
    rm -f "${plan_file}"
  )
}

terraform_output_raw() {
  local dir="${1}" name="${2}"
  (
    cd "${dir}"
    tf output -raw "${name}"
  )
}

run_output_command() {
  local dir="${1}" output_name="${2}"
  bash -lc "$(terraform_output_raw "${dir}" "${output_name}")"
}
