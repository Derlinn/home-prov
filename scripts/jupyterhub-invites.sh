#!/usr/bin/env bash
# Short-lived JupyterHub guest accounts (Authentik users in linderis_jupyterhub).
#
# JupyterHub trusts any Authentik user passing the application policy, so guests
# live outside Git: no manifest change and no Flux involved.
set -euo pipefail

AUTHENTIK_URL="${AUTHENTIK_URL:-https://authentik.linderis.fr}"
AUTHENTIK_TOKEN="${AUTHENTIK_TOKEN:-}"
HUB_URL="${JUPYTERHUB_URL:-https://jupyterhub.linderis.fr}"
HUB_TOKEN="${JUPYTERHUB_TOKEN:-}"
NAMESPACE="${JUPYTERHUB_NAMESPACE:-devtools}"
GROUP_NAME="${JUPYTERHUB_GROUP:-linderis_jupyterhub}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <create|delete|list|share> [options]

  create USERNAME [--name "Full Name"] [--email addr] [--password pw]
  create --prefix PREFIX --count N [--start N]
  delete USERNAME [--keep-volume]
  delete --prefix PREFIX --count N [--start N] [--keep-volume]
  list
  share FROM_USERNAME [--user USERNAME | --group GROUP] [--allow-start]
  share --for STUDENT [--allow-start]   (owner auto: groupe-ceil(N/5))

Env: AUTHENTIK_TOKEN (create/delete/list, platform host), JUPYTERHUB_TOKEN (share:
your own Hub token from Hub Control Panel -> Token, or an admin token),
AUTHENTIK_URL, JUPYTERHUB_URL.
EOF
  exit "${1:-0}"
}

die() { echo "error: $*" >&2; exit 1; }

api() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -X "${method}" -H "Authorization: Bearer ${AUTHENTIK_TOKEN}")
  [[ -n "${data}" ]] && args+=(-H "Content-Type: application/json" -d "${data}")
  curl "${args[@]}" "${AUTHENTIK_URL}/api/v3${path}"
}

api_code() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -o /dev/null -w "%{http_code}" -X "${method}" -H "Authorization: Bearer ${AUTHENTIK_TOKEN}")
  [[ -n "${data}" ]] && args+=(-H "Content-Type: application/json" -d "${data}")
  curl "${args[@]}" "${AUTHENTIK_URL}/api/v3${path}"
}

check_username() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$ ]] \
    || die "username must be lowercase alphanumeric plus ._- (Authentik/URL-safe): $1"
}

group_pk() {
  api GET "/core/groups/?name=${GROUP_NAME}" | jq -r '.results[0].pk // empty'
}

user_pk() {
  api GET "/core/users/?username=$1" | jq -r '.results[0].pk // empty'
}

create_one() {
  local username="$1" name="$2" email="$3" password="$4" gpk="$5" upk payload
  [[ -n "$(user_pk "${username}")" ]] && die "user already exists: ${username}"

  payload="$(jq -n --arg u "${username}" --arg n "${name:-${username}}" --arg e "${email}" \
    '{username: $u, name: $n, is_active: true} + (if $e == "" then {} else {email: $e} end)')"
  upk="$(api POST /core/users/ "${payload}" | jq -r '.pk // empty')"
  [[ -n "${upk}" ]] || die "user creation failed: ${username}"

  [[ -n "${password}" ]] || password="$(openssl rand -base64 16)"
  [[ "$(api_code POST "/core/users/${upk}/set_password/" "$(jq -n --arg p "${password}" '{password: $p}')")" == "204" ]] \
    || die "set_password failed: ${username}"
  [[ "$(api_code POST "/core/groups/${gpk}/add_user/" "$(jq -n --argjson p "${upk}" '{pk: $p}')")" == "204" ]] \
    || die "add to group failed: ${username}"
  echo "${username} ${password}"
}

batch_names() {
  local prefix="$1" count="$2" start="$3" last width i
  last=$((start + count - 1))
  width=${#last}
  for ((i = start; i <= last; i++)); do
    printf '%s-%0*d\n' "${prefix}" "${width}" "$i"
  done
}

cmd_create() {
  local username="" prefix="" count=1 start=1 name="" email="" password=""
  while (($#)); do
    case "$1" in
      --prefix) prefix="$2"; shift 2 ;;
      --count) count="$2"; shift 2 ;;
      --start) start="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --email) email="$2"; shift 2 ;;
      --password) password="$2"; shift 2 ;;
      -*) die "unknown option: $1" ;;
      *) [[ -z "${username}" ]] || die "only one USERNAME"; username="$1"; shift ;;
    esac
  done

  if [[ -n "${prefix}" ]]; then
    [[ -z "${username}" ]] || die "USERNAME and --prefix are exclusive"
    [[ -z "${password}" && -z "${name}" && -z "${email}" ]] \
      || die "--password/--name/--email cannot be combined with --prefix"
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -ge 1 ]] || die "--count must be >= 1"
    [[ "${start}" =~ ^[0-9]+$ && "${start}" -ge 1 ]] || die "--start must be >= 1"
  else
    [[ -n "${username}" ]] || die "missing USERNAME or --prefix"
  fi

  local gpk
  gpk="$(group_pk)" && [[ -n "${gpk}" ]] || die "group not found: ${GROUP_NAME}"

  if [[ -n "${prefix}" ]]; then
    local names existing=() n
    names="$(batch_names "${prefix}" "${count}" "${start}")"
    while read -r n; do
      check_username "${n}"
      [[ -z "$(user_pk "${n}")" ]] || existing+=("${n}")
    done <<<"${names}"
    ((${#existing[@]} == 0)) || die "already exist: ${existing[*]} (use --start to continue)"
    printf '%-24s %s\n' "USERNAME" "PASSWORD"
    while read -r n; do
      out="$(create_one "${n}" "" "" "" "${gpk}")"
      printf '%-24s %s\n' ${out}
    done <<<"${names}"
    echo "login: https://jupyterhub.linderis.fr (Sign in with Authentik)"
    return
  fi

  check_username "${username}"
  out="$(create_one "${username}" "${name}" "${email}" "${password}" "${gpk}")"
  echo "username: ${out%% *}"
  echo "password: ${out##* }"
  echo "login:    https://jupyterhub.linderis.fr (Sign in with Authentik)"
}

delete_one() {
  local username="$1" keep_volume="$2" upk
  upk="$(user_pk "${username}")" && [[ -n "${upk}" ]] || die "user not found: ${username}"

  kubectl -n "${NAMESPACE}" delete pod -l "hub.jupyter.org/username=${username}" --ignore-not-found
  [[ "${keep_volume}" == "true" ]] \
    || kubectl -n "${NAMESPACE}" delete pvc -l "hub.jupyter.org/username=${username}" --ignore-not-found
  [[ "$(api_code DELETE "/core/users/${upk}/")" == "204" ]] || die "user deletion failed: ${username}"
  echo "deleted: ${username}"
}

cmd_delete() {
  local username="" prefix="" count=1 start=1 keep_volume="false"
  while (($#)); do
    case "$1" in
      --prefix) prefix="$2"; shift 2 ;;
      --count) count="$2"; shift 2 ;;
      --start) start="$2"; shift 2 ;;
      --keep-volume) keep_volume="true"; shift ;;
      -*) die "unknown option: $1" ;;
      *) [[ -z "${username}" ]] || die "only one USERNAME"; username="$1"; shift ;;
    esac
  done
  if [[ -n "${prefix}" ]]; then
    [[ -z "${username}" ]] || die "USERNAME and --prefix are exclusive"
    [[ "${count}" =~ ^[0-9]+$ && "${count}" -ge 1 ]] || die "--count must be >= 1"
    [[ "${start}" =~ ^[0-9]+$ && "${start}" -ge 1 ]] || die "--start must be >= 1"
    local n
    while read -r n; do
      check_username "${n}"
      delete_one "${n}" "${keep_volume}"
    done <<<"$(batch_names "${prefix}" "${count}" "${start}")"
    return
  fi
  [[ -n "${username}" ]] || die "missing USERNAME or --prefix"
  check_username "${username}"
  delete_one "${username}" "${keep_volume}"
}

cmd_list() {
  local gpk users
  gpk="$(group_pk)" && [[ -n "${gpk}" ]] || die "group not found: ${GROUP_NAME}"
  users="$(api GET "/core/groups/${gpk}/" | jq -r '.users[]?')"
  [[ -n "${users}" ]] || { echo "no members in ${GROUP_NAME}"; return; }
  for u in ${users}; do
    api GET "/core/users/${u}/" | jq -r '"\(.username)\t\(.name)\tactive=\(.is_active)"'
  done
}

cmd_share() {
  local from="" user="" group="" allow_start="false" auto="false"
  if [[ "${1:-}" == "--for" ]]; then
    auto="true"
    local student="${2:-}" num grp
    [[ -n "${student}" ]] || die "share --for needs a STUDENT username"
    check_username "${student}"
    [[ "${student}" =~ -([0-9]+)$ ]] || die "--for needs a username ending with -N (e.g. ensimag-7)"
    num="${BASH_REMATCH[1]}"
    grp=$(( (10#${num} + 4) / 5 ))
    from="groupe-${grp}"
    user="${student}"
    shift 2
  else
    from="$1"
    shift
    check_username "${from}"
  fi
  while (($#)); do
    case "$1" in
      --user) [[ "${auto}" == "false" ]] || die "--user cannot be combined with --for"; user="$2"; shift 2 ;;
      --group) [[ "${auto}" == "false" ]] || die "--group cannot be combined with --for"; group="$2"; shift 2 ;;
      --allow-start) allow_start="true"; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [[ -n "${user}" || -n "${group}" ]] || die "share needs --user or --group"
  [[ -z "${user}" || -z "${group}" ]] || die "--user and --group are exclusive"
  [[ -z "${user}" ]] || check_username "${user}"
  if [[ "${auto}" == "true" ]]; then
    [[ -n "${AUTHENTIK_TOKEN}" ]] || die "set AUTHENTIK_TOKEN (Authentik Tokens & App passwords, intent API)"
    [[ -n "$(user_pk "${from}")" ]] || die "owner account '${from}' does not exist (create it first)"
    [[ -n "$(user_pk "${user}")" ]] || die "user not found: ${user}"
  fi
  [[ -n "${HUB_TOKEN}" ]] || die "set JUPYTERHUB_TOKEN (your Hub token from Hub Control Panel -> Token)"

  local target payload code
  target="${from}/"
  if [[ -n "${user}" ]]; then
    payload="$(jq -n --arg u "${user}" '{user: $u}')"
  else
    payload="$(jq -n --arg g "${group}" '{group: $g}')"
  fi
  if [[ "${allow_start}" == "true" ]]; then
    payload="$(jq --arg s "${target}" '. + {scopes: ["access:servers!server=\($s)", "servers!server=\($s)"]}' <<<"${payload}")"
  fi
  code="$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${HUB_TOKEN}" -H "Content-Type: application/json" \
    -d "${payload}" "${HUB_URL}/hub/api/shares/${target}")"
  [[ "${code}" == 2* ]] || die "share failed (http ${code})"
  echo "shared: ${from}'s server -> ${user:-group ${group}}"
  echo "open:   ${HUB_URL}/user/${from}/lab"
}

  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0
command -v curl jq kubectl openssl >/dev/null || die "requires: curl jq kubectl openssl"

case "${1:-}" in
  create|delete|list)
    [[ -n "${AUTHENTIK_TOKEN}" ]] || die "set AUTHENTIK_TOKEN (Authentik Tokens & App passwords, intent API)" ;;
  share)
    [[ $# -ge 2 ]] || usage 1
    [[ "${2:-}" == "-h" || "${2:-}" == "--help" ]] && usage 0 ;;  
  *) usage 1 ;;
esac

case "${1:-}" in
  create) [[ $# -ge 2 ]] || usage 1; cmd_create "${@:2}" ;;
  delete) [[ $# -ge 2 ]] || usage 1; cmd_delete "${@:2}" ;;
  list) cmd_list ;;
  share) cmd_share "${@:2}" ;;
  *) usage 1 ;;
esac
