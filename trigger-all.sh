#!/bin/bash
# ─── Trigger tests on all 20 EC2 instances with unique SERVER_IDs ────────────
#
# Each server runs with SERVER_ID=N so it loads its own session-N.json
#
# Usage:
#   ./trigger-all.sh --key ~/.ssh/your-key.pem

set -euo pipefail

KEY_FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --key) KEY_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$KEY_FILE" ]]; then
  echo "Usage: ./trigger-all.sh --key ~/.ssh/your-key.pem"
  exit 1
fi

echo "Fetching rayna-automation instance IPs..."
IPS=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=rayna-automation" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)

COUNT=$(echo "$IPS" | wc -w)
echo "Triggering tests on $COUNT instances..."

INDEX=1
for IP in $IPS; do
  echo "  [$INDEX/$COUNT] $IP — starting tests with SERVER_ID=$INDEX..."
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "ubuntu@${IP}" \
    "nohup sudo -u appuser bash -c 'export DISPLAY=:99 && export SERVER_ID=$INDEX && export TOTAL_SERVERS=$COUNT && cd /home/appuser/app && npm test' > /home/appuser/test-output.log 2>&1 &" &
  INDEX=$((INDEX + 1))
done

wait
echo ""
echo "Tests triggered on all $COUNT instances (each with unique SERVER_ID)."
echo ""
echo "Monitor a specific server:"
echo "  ssh -i $KEY_FILE ubuntu@<ip> 'tail -f /home/appuser/test-output.log'"
