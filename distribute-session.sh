#!/bin/bash
# ─── Distribute unique sessions to all 20 EC2 instances ──────────────────────
#
# Workflow:
#   1. Run "npm run auth:all" locally → solve CAPTCHA 20 times
#      → saves auth/sessions/session-1.json through session-20.json
#   2. Run this script to push each session to its matching server
#
# Usage:
#   ./distribute-session.sh --key ~/.ssh/your-key.pem

set -euo pipefail

KEY_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --key) KEY_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$KEY_FILE" ]]; then
  echo "Usage: ./distribute-session.sh --key ~/.ssh/your-key.pem"
  exit 1
fi

SESSIONS_DIR="auth/sessions"
if [[ ! -d "$SESSIONS_DIR" ]]; then
  echo "ERROR: $SESSIONS_DIR/ not found. Run 'npm run auth:all' first."
  exit 1
fi

# Count available session files
SESSION_COUNT=$(ls "$SESSIONS_DIR"/session-*.json 2>/dev/null | wc -l)
if [[ "$SESSION_COUNT" -eq 0 ]]; then
  echo "ERROR: No session files found in $SESSIONS_DIR/"
  echo "Run 'npm run auth:all' first to generate 20 sessions."
  exit 1
fi
echo "Found $SESSION_COUNT session files."

# Get all running instance IPs tagged with our project
echo "Fetching rayna-automation instance IPs..."
IPS=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=rayna-automation" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

if [[ -z "$IPS" ]]; then
  echo "ERROR: No running instances found with tag Name=rayna-automation"
  exit 1
fi

# Distribute: server 1 gets session-1.json, server 2 gets session-2.json, etc.
INDEX=1
FAILED=0
for IP in $IPS; do
  SESSION_FILE="$SESSIONS_DIR/session-${INDEX}.json"

  if [[ ! -f "$SESSION_FILE" ]]; then
    echo "  [$INDEX] $IP — SKIPPED (session-${INDEX}.json not found)"
    FAILED=$((FAILED + 1))
    INDEX=$((INDEX + 1))
    continue
  fi

  echo -n "  [$INDEX] $IP — uploading session-${INDEX}.json... "

  # Create sessions dir on the server
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "ubuntu@${IP}" "sudo -u appuser mkdir -p /home/appuser/app/auth/sessions" 2>/dev/null

  # Upload the unique session file
  scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "$SESSION_FILE" "ubuntu@${IP}:/home/appuser/app/auth/sessions/session-${INDEX}.json" 2>/dev/null

  # Fix ownership
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "ubuntu@${IP}" "sudo chown -R appuser:appuser /home/appuser/app/auth/sessions/" 2>/dev/null

  echo "OK"
  INDEX=$((INDEX + 1))
done

TOTAL=$((INDEX - 1))
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Done: $((TOTAL - FAILED))/$TOTAL instances received unique sessions"
if [[ $FAILED -gt 0 ]]; then
  echo " WARNING: $FAILED instances skipped or failed"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""
echo " Next: ./trigger-all.sh --key $KEY_FILE"
