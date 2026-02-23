#!/bin/bash
# ─── Distribute session.json to all 20 EC2 instances ─────────────────────────
#
# Workflow:
#   1. Run "npm run auth" locally → solve CAPTCHA → session.json saved
#   2. Run this script to push session.json to all EC2 instances
#   3. Run trigger-all.sh to start tests on all servers
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

SESSION_FILE="auth/session.json"
if [[ ! -f "$SESSION_FILE" ]]; then
  echo "ERROR: $SESSION_FILE not found. Run 'npm run auth' first."
  exit 1
fi

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

COUNT=$(echo "$IPS" | wc -w)
echo "Found $COUNT instances."

INDEX=1
for IP in $IPS; do
  echo -n "  [$INDEX/$COUNT] $IP — uploading... "
  scp -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "$SESSION_FILE" "ubuntu@${IP}:/home/appuser/app/auth/session.json" 2>/dev/null
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "ubuntu@${IP}" "sudo chown appuser:appuser /home/appuser/app/auth/session.json" 2>/dev/null
  echo "OK"
  INDEX=$((INDEX + 1))
done

echo ""
echo "Session distributed to $COUNT instances."
echo "Now run: ./trigger-all.sh --key $KEY_FILE"
