#!/bin/bash

set -euo pipefail

info() {
  local message="$1"
  echo "[INFO] ${message}"
}

error() {
  local message="$1"
  echo ""
  echo "[ERROR] ${message}"
}

fatal() {
  local message="$1"

  error "$message"
  exit 1
}
