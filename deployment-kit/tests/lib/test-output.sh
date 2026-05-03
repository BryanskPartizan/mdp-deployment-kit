#!/usr/bin/env bash
# Единый компактный вывод тестов и публикация результата в demo-приложение.
set -euo pipefail

TEST_ENV_NAME=${ENV_NAME:-vm-dev}
TEST_RESULTS_DIR=${TEST_RESULTS_DIR:-.artifacts/${TEST_ENV_NAME}/test-results}
TEST_PUBLISH_RESULTS=${TEST_PUBLISH_RESULTS:-true}
APP_DOMAIN=${APP_DOMAIN:-pkhco.ru}
GATEWAY_HOST=${GATEWAY_HOST:-gateway.${APP_DOMAIN}}

TEST_SUITE_NAME=""
TEST_SUITE_TITLE=""
TEST_RUN_ID=""
TEST_STARTED_AT=0
TEST_FAILED=0
TEST_TOTAL=0
TEST_PASSED=0
TEST_TSV_FILE=""
TEST_JSON_FILE=""
TEST_HTML_FILE=""

json_escape() {
  if command -v jq >/dev/null 2>&1; then
    jq -Rn --arg value "$1" '$value'
  else
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

html_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

suite_start() {
  TEST_SUITE_NAME="$1"
  TEST_SUITE_TITLE="$2"
  TEST_RUN_ID="${TEST_SUITE_NAME}-$(date +%Y%m%dT%H%M%S)"
  TEST_STARTED_AT=$(date +%s)
  TEST_FAILED=0
  TEST_TOTAL=0
  TEST_PASSED=0
  mkdir -p "$TEST_RESULTS_DIR/logs"
  TEST_TSV_FILE="${TEST_RESULTS_DIR}/${TEST_RUN_ID}.tsv"
  TEST_JSON_FILE="${TEST_RESULTS_DIR}/${TEST_RUN_ID}.json"
  TEST_HTML_FILE="${TEST_RESULTS_DIR}/${TEST_RUN_ID}.html"
  : > "$TEST_TSV_FILE"
  printf '\n== %s ==\n' "$TEST_SUITE_TITLE"
}

record_check() {
  local status="$1"
  local title="$2"
  local duration="$3"
  local log_file="$4"
  printf '%s\t%s\t%s\t%s\n' "$status" "$title" "$duration" "$log_file" >> "$TEST_TSV_FILE"
}

run_check() {
  local title="$1"
  shift
  local safe_name
  local log_file
  local started
  local finished
  local duration
  local check_index

  TEST_TOTAL=$((TEST_TOTAL + 1))
  check_index=$TEST_TOTAL
  safe_name=$(printf '%s' "$title" | tr -cs '[:alnum:]' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-//; s/-$//')
  log_file="${TEST_RESULTS_DIR}/logs/${TEST_RUN_ID}-${check_index}-${safe_name:-check}.log"
  started=$(date +%s)

  printf '  • %-58s' "$title"
  if "$@" > "$log_file" 2>&1; then
    finished=$(date +%s)
    duration=$((finished - started))
    TEST_PASSED=$((TEST_PASSED + 1))
    record_check "ok" "$title" "$duration" "$log_file"
    printf 'OK (%ss)\n' "$duration"
  else
    finished=$(date +%s)
    duration=$((finished - started))
    TEST_FAILED=1
    record_check "fail" "$title" "$duration" "$log_file"
    printf 'FAIL (%ss)\n' "$duration"
    printf '    Лог: %s\n' "$log_file"
    tail -40 "$log_file" | sed 's/^/    | /'
  fi
}

write_json_report() {
  local finished_at
  local duration
  local status
  local first=1
  finished_at=$(date +%s)
  duration=$((finished_at - TEST_STARTED_AT))
  status="ok"
  [[ "$TEST_FAILED" -eq 0 ]] || status="fail"

  {
    printf '{\n'
    printf '  "id": %s,\n' "$(json_escape "$TEST_RUN_ID")"
    printf '  "suite": %s,\n' "$(json_escape "$TEST_SUITE_NAME")"
    printf '  "title": %s,\n' "$(json_escape "$TEST_SUITE_TITLE")"
    printf '  "status": %s,\n' "$(json_escape "$status")"
    printf '  "durationSeconds": %s,\n' "$duration"
    printf '  "createdAt": %s,\n' "$(json_escape "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
    printf '  "summary": %s,\n' "$(json_escape "${TEST_PASSED}/${TEST_TOTAL} проверок OK")"
    printf '  "checks": [\n'
    while IFS=$'\t' read -r check_status check_title check_duration check_log; do
      [[ -n "${check_status:-}" ]] || continue
      if [[ "$first" -eq 0 ]]; then
        printf ',\n'
      fi
      first=0
      printf '    {"status": %s, "title": %s, "durationSeconds": %s, "log": %s}' \
        "$(json_escape "$check_status")" \
        "$(json_escape "$check_title")" \
        "$check_duration" \
        "$(json_escape "$check_log")"
    done < "$TEST_TSV_FILE"
    printf '\n  ]\n'
    printf '}\n'
  } > "$TEST_JSON_FILE"
  cp "$TEST_JSON_FILE" "${TEST_RESULTS_DIR}/latest.json"
}

write_html_report() {
  local status_class="ok"
  [[ "$TEST_FAILED" -eq 0 ]] || status_class="fail"

  {
    cat <<HTML
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>${TEST_SUITE_TITLE}</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 24px; color: #172033; background: #f6f7f9; }
    main { max-width: 960px; margin: 0 auto; background: #fff; border: 1px solid #d8dee8; border-radius: 8px; padding: 20px; }
    h1 { margin-top: 0; font-size: 22px; }
    .ok { color: #16865a; } .fail { color: #b42318; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 9px 10px; border-bottom: 1px solid #edf0f5; text-align: left; }
    th { background: #f8fafc; }
  </style>
</head>
<body>
<main>
  <h1>${TEST_SUITE_TITLE}</h1>
  <p class="${status_class}">Результат: ${TEST_PASSED}/${TEST_TOTAL} проверок OK</p>
  <table>
    <thead><tr><th>Статус</th><th>Проверка</th><th>Время</th><th>Лог</th></tr></thead>
    <tbody>
HTML
    while IFS=$'\t' read -r check_status check_title check_duration check_log; do
      [[ -n "${check_status:-}" ]] || continue
      printf '      <tr><td class="%s">%s</td><td>%s</td><td>%ss</td><td>%s</td></tr>\n' \
        "$(html_escape "$check_status")" \
        "$(html_escape "$check_status")" \
        "$(html_escape "$check_title")" \
        "$(html_escape "$check_duration")" \
        "$(html_escape "$check_log")"
    done < "$TEST_TSV_FILE"
    cat <<HTML
    </tbody>
  </table>
</main>
</body>
</html>
HTML
  } > "$TEST_HTML_FILE"
  cp "$TEST_HTML_FILE" "${TEST_RESULTS_DIR}/latest.html"
}

publish_report() {
  [[ "$TEST_PUBLISH_RESULTS" == "true" ]] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local outputs=".artifacts/${TEST_ENV_NAME}/terraform-outputs.json"
  [[ -f "$outputs" ]] || return 0

  local ingress_ip
  ingress_ip=$(jq -r '.ingress_external_ip.value // empty' "$outputs")
  [[ -n "$ingress_ip" ]] || return 0

  curl -kfsS \
    --resolve "${GATEWAY_HOST}:443:${ingress_ip}" \
    -H 'content-type: application/json' \
    --data @"$TEST_JSON_FILE" \
    "https://${GATEWAY_HOST}/test-runs" >/dev/null 2>&1 || true
}

suite_finish() {
  write_json_report
  write_html_report
  publish_report
  printf 'Итог: %s/%s OK. JSON: %s HTML: %s\n' "$TEST_PASSED" "$TEST_TOTAL" "$TEST_JSON_FILE" "$TEST_HTML_FILE"
  [[ "$TEST_FAILED" -eq 0 ]]
}
