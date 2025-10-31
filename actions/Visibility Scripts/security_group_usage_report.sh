#!/bin/bash

echo "Generating full security group usage report..."

# Output header
echo "SecurityGroupId,GroupName,AssociatedWith" > security_group_usage_report.csv

# Get all security groups
aws ec2 describe-security-groups --query 'SecurityGroups[*]' --output json | jq -c '.[]' | while read -r sg; do
  sg_id=$(echo "$sg" | jq -r '.GroupId')
  sg_name=$(echo "$sg" | jq -r '.GroupName')
  associated="None"

  # Check EC2 instances
  ec2_match=$(aws ec2 describe-instances \
    --query "Reservations[*].Instances[*].SecurityGroups[?GroupId=='$sg_id']" \
    --output text)
  if [ -n "$ec2_match" ]; then associated="EC2 Instance"; fi

  # Check ENIs
  eni_match=$(aws ec2 describe-network-interfaces \
    --query "NetworkInterfaces[*].Groups[?GroupId=='$sg_id']" \
    --output text)
  if [ -n "$eni_match" ]; then associated="ENI"; fi

  # Check RDS
  rds_match=$(aws rds describe-db-instances \
    --query "DBInstances[*].VpcSecurityGroups[?VpcSecurityGroupId=='$sg_id']" \
    --output text)
  if [ -n "$rds_match" ]; then associated="RDS"; fi

  # Check Load Balancers
  elb_match=$(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[*].SecurityGroups[?contains(@, '$sg_id')]" \
    --output text)
  if [ -n "$elb_match" ]; then associated="Load Balancer"; fi

  # Check VPC Endpoints
  vpce_match=$(aws ec2 describe-vpc-endpoints \
    --query "VpcEndpoints[*].Groups[?GroupId=='$sg_id']" \
    --output text)
  if [ -n "$vpce_match" ]; then associated="VPC Endpoint"; fi

  # Write to CSV
  echo "$sg_id,$sg_name,$associated" >> security_group_usage_report.csv
done

echo "✅ Report complete: security_group_usage_report.csv"

