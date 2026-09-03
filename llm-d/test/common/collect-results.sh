#!/usr/bin/env bash
# Collect GuideLLM benchmark results from a completed job pod.

RESULT_FILES=(
  benchmark.json
  benchmark.csv
)

decode_base64() {
  if base64 -d </dev/null 2>/dev/null; then
    base64 -d
  else
    base64 -D
  fi
}

copy_from_pod() {
  local namespace="${1}"
  local pod="${2}"
  local remote_path="${3}"
  local local_path="${4}"
  local container="${5:-guidellm}"

  if oc cp -n "${namespace}" -c "${container}" \
    "${namespace}/${pod}:${remote_path}" "${local_path}" 2>/dev/null; then
    return 0
  fi

  if oc cp -n "${namespace}" -c "${container}" \
    "${pod}:${remote_path}" "${local_path}" 2>/dev/null; then
    return 0
  fi

  return 1
}

extract_file_from_logs() {
  local logs_file="${1}"
  local file="${2}"
  local local_path="${3}"

  awk -v begin="===GUIDELLM_FILE_BEGIN:${file}===" -v end="===GUIDELLM_FILE_END:${file}===" '
    $0 == begin { found=1; next }
    $0 == end { found=0; next }
    found { print }
  ' "${logs_file}" | decode_base64 > "${local_path}" 2>/dev/null
}

collect_results() {
  local scenario_dir="${1:?scenario directory required}"
  local job_name="${2:?job name required}"
  local namespace="${3:-demo-llm}"
  local results_dir="${scenario_dir}/results"
  local copied=0
  local failed=0
  local pod logs

  mkdir -p "${results_dir}"

  pod="$(oc get pods -n "${namespace}" \
    -l "job-name=${job_name}" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

  if [[ -z "${pod}" ]]; then
    echo "ERROR: No pod found for job ${job_name} in ${namespace}" >&2
    return 1
  fi

  echo "Collecting results from pod ${pod}..."
  logs="$(oc logs -n "${namespace}" -c guidellm "${pod}" 2>/dev/null || true)"
  if [[ -n "${logs}" ]]; then
    printf '%s\n' "${logs}" > "${results_dir}/benchmark.log"
    echo "  saved benchmark.log"
  fi

  for file in "${RESULT_FILES[@]}"; do
    local_path="${results_dir}/${file}"
    if copy_from_pod "${namespace}" "${pod}" "/results/${file}" "${local_path}"; then
      echo "  copied ${file} (oc cp)"
      copied=$((copied + 1))
      continue
    fi

    if [[ -f "${results_dir}/benchmark.log" ]] \
      && extract_file_from_logs "${results_dir}/benchmark.log" "${file}" "${local_path}" \
      && [[ -s "${local_path}" ]]; then
      echo "  extracted ${file} (pod logs)"
      copied=$((copied + 1))
      continue
    fi

    echo "  WARN: could not collect ${file} from pod ${pod}" >&2
    failed=$((failed + 1))
  done

  if [[ "${copied}" -eq 0 ]]; then
    echo "ERROR: No result files collected from pod ${pod}" >&2
    echo "See ${results_dir}/benchmark.log for guidellm output." >&2
    return 1
  fi

  cat > "${results_dir}/run-metadata.txt" <<EOF
scenario_dir=${scenario_dir}
job_name=${job_name}
namespace=${namespace}
pod=${pod}
collected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
gateway_host=${GATEWAY_HOST:-unknown}
llm_url=${LLM_URL:-unknown}
start_time=${START_TIME:-unknown}
end_time=${END_TIME:-unknown}
files_copied=${copied}
files_failed=${failed}
EOF

  echo "Results saved to ${results_dir}/ (${copied} file(s))"
  ls -la "${results_dir}/" || true
}
