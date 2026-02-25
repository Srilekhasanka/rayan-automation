#!/bin/bash
# ─── Deploy 20 Ubuntu EC2 instances with the automation script ───────────────
#
# Prerequisites:
#   1. AWS CLI configured: aws configure
#   2. Replace the values below with your actual AWS resources
#
# Usage:
#   chmod +x deploy-ec2.sh
#   ./deploy-ec2.sh

set -euo pipefail

# ─── Configuration (CHANGE THESE) ───────────────────────────────────────────
AMI_ID="ami-0e2c8caa4b6378d8c"          # Ubuntu 24.04 LTS (us-east-1) — change per region
INSTANCE_TYPE="t3.xlarge"                 # 4 vCPU, 16 GB RAM
KEY_NAME="your-key-pair-name"             # Your SSH key pair name
SECURITY_GROUP_ID="sg-xxxxxxxxxxxxxxxxx"  # SG allowing SSH (22) inbound
SUBNET_ID="subnet-xxxxxxxxxxxxxxxxx"      # Your subnet ID
INSTANCE_COUNT=20                         # Number of servers to deploy
USERDATA_FILE="ec2-userdata.sh"           # User data script path

# ─── Launch instances ────────────────────────────────────────────────────────
echo "Launching $INSTANCE_COUNT Ubuntu instances..."

INSTANCE_IDS=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --count "$INSTANCE_COUNT" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --subnet-id "$SUBNET_ID" \
  --user-data "file://$USERDATA_FILE" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rayna-automation},{Key=Project,Value=visa-automation}]" \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --query 'Instances[].InstanceId' \
  --output text)

echo "Launched instances: $INSTANCE_IDS"

# ─── Wait for instances to be running ────────────────────────────────────────
echo "Waiting for instances to enter 'running' state..."
aws ec2 wait instance-running --instance-ids $INSTANCE_IDS
echo "All instances are running."

# ─── Get public IPs ─────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Instance IPs (save these for SSH/VNC access)"
echo "═══════════════════════════════════════════════════════════"

INDEX=1
for INSTANCE_ID in $INSTANCE_IDS; do
  PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  echo "  Server $INDEX: $INSTANCE_ID → $PUBLIC_IP"
  INDEX=$((INDEX + 1))
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Next steps:"
echo "═══════════════════════════════════════════════════════════"
echo "  1. Wait ~5 min for setup to complete"
echo "  2. Locally: npm run auth:all  (solve CAPTCHA 20 times)"
echo "  3. ./distribute-session.sh --key ~/.ssh/<key>.pem"
echo "  4. ./trigger-all.sh --key ~/.ssh/<key>.pem"
echo "═══════════════════════════════════════════════════════════"
