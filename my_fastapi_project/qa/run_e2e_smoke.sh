#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/run_smoke_order_flow.py"

: "${BASE_URL:?Missing BASE_URL env var}"
: "${EMPLOYEE_EMAIL:?Missing EMPLOYEE_EMAIL env var}"
: "${EMPLOYEE_PASSWORD:?Missing EMPLOYEE_PASSWORD env var}"
: "${DRIVER_EMAIL:?Missing DRIVER_EMAIL env var}"
: "${DRIVER_PASSWORD:?Missing DRIVER_PASSWORD env var}"

python3 "${SCRIPT_PATH}"
