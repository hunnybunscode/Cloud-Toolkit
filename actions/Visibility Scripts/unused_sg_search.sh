#!/bin/bash

echo "Scanning for unused security groups..."

# Get all security group IDs
all_sgs=$(aws ec2 describe-security-groups --query 'SecurityGroups[*].GroupId' --output text)

# EC2 instances
ec2_sgs=$(aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' \
  --output text)

# ENIs
eni_sgs=$(aws ec2 describe-network-interfaces \
  --query 'NetworkInterfaces[*].Groups[*].GroupId' \
  --output text)

# RDS instances
rds_sgs=$(aws rds describe-db-instances \
  --query 'DBInstances[*].VpcSecurityGroups[*].VpcSecurityGroupId' \
  --output text)

# Load balancers (ALB/NLB)
elb_sgs=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[*].SecurityGroups' \
  --output text)

# VPC Endpoints (Interface type only)
vpce_sgs=$(aws ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[*].Groups[*].GroupId' \
  --output text)

# Combine all used SGs
used_sgs=$(echo -e "$ec2_sgs\n$eni_sgs\n$rds_sgs\n$elb_sgs\n$vpce_sgs" | tr '\t' '\n' | sort -u)

# Compare and find unused SGs
echo "UnusedSecurityGroupId,GroupName" > unused_security_groups.csv
for sg in $all_sgs; do
  if ! echo "$used_sgs" | grep -q "$sg"; then
    name=$(aws ec2 describe-security-groups --group-ids "$sg" \
      --query 'SecurityGroups[0].GroupName' --output text)
    echo "$sg,$name" >> unused_security_groups.csv
  fi
done

echo "✅ Done! Results saved to unused_security_groups.csv"

