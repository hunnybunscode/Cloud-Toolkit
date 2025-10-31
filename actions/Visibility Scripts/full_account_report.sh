#!/bin/bash

# Output CSV header for EC2 section
echo "InstanceId,InstanceName,AvailabilityZone,VolumeId,Encrypted,SecurityGroups" > aws_account_report.csv

# EC2 + EBS + Security Groups
aws ec2 describe-instances --query 'Reservations[*].Instances[*]' --output json | jq -c '.[][]' | while read -r instance; do
  instance_id=$(echo "$instance" | jq -r '.InstanceId')
  instance_name=$(echo "$instance" | jq -r '.Tags[]? | select(.Key=="Name") | .Value')
  az=$(echo "$instance" | jq -r '.Placement.AvailabilityZone')
  sg_list=$(echo "$instance" | jq -r '[.SecurityGroups[]?.GroupId] | join(";")')

  echo "$instance" | jq -c '.BlockDeviceMappings[]?' | while read -r mapping; do
    volume_id=$(echo "$mapping" | jq -r '.Ebs.VolumeId')
    encrypted=$(aws ec2 describe-volumes --volume-ids "$volume_id" --query 'Volumes[0].Encrypted' --output text)
    echo "$instance_id,$instance_name,$az,$volume_id,$encrypted,$sg_list" >> aws_account_report.csv
  done
done

# Security Groups and Rules
echo "" >> aws_account_report.csv
echo "SecurityGroupId,GroupName,Protocol,PortRange,Source" >> aws_account_report.csv

aws ec2 describe-security-groups --query 'SecurityGroups[*]' --output json | jq -c '.[]' | while read -r sg; do
  sg_id=$(echo "$sg" | jq -r '.GroupId')
  sg_name=$(echo "$sg" | jq -r '.GroupName')

  echo "$sg" | jq -c '.IpPermissions[]?' | while read -r rule; do
    protocol=$(echo "$rule" | jq -r '.IpProtocol')
    from_port=$(echo "$rule" | jq -r '.FromPort // "All"')
    to_port=$(echo "$rule" | jq -r '.ToPort // "All"')
    port_range="$from_port-$to_port"
    sources=$(echo "$rule" | jq -r '[.IpRanges[]?.CidrIp, .UserIdGroupPairs[]?.GroupId] | join(";")')
    echo "$sg_id,$sg_name,$protocol,$port_range,$sources" >> aws_account_report.csv
  done
done

# S3 Buckets (no size)
echo "" >> aws_account_report.csv
echo "BucketName,Region,VersioningEnabled" >> aws_account_report.csv

aws s3api list-buckets --query 'Buckets[*].Name' --output text | tr '\t' '\n' | while read -r bucket; do
  region=$(aws s3api get-bucket-location --bucket "$bucket" --query 'LocationConstraint' --output text)
  if [ "$region" == "None" ]; then region="us-east-1"; fi
  versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --query 'Status' --output text)
  if [ "$versioning" == "Enabled" ]; then versioning_enabled="true"; else versioning_enabled="false"; fi
  echo "$bucket,$region,$versioning_enabled" >> aws_account_report.csv
done

# Subnets and Route Tables
echo "" >> aws_account_report.csv
echo "SubnetId,SubnetName,VpcId,AvailabilityZone,RouteTableId,DestinationCidr,Target" >> aws_account_report.csv

aws ec2 describe-subnets --query 'Subnets[*]' --output json | jq -c '.[]' | while read -r subnet; do
  subnet_id=$(echo "$subnet" | jq -r '.SubnetId')
  subnet_name=$(echo "$subnet" | jq -r '.Tags[]? | select(.Key=="Name") | .Value')
  vpc_id=$(echo "$subnet" | jq -r '.VpcId')
  az=$(echo "$subnet" | jq -r '.AvailabilityZone')

  # Find route table associated with subnet
  rt_id=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$subnet_id" \
    --query 'RouteTables[0].RouteTableId' --output text)

  # Get route table entries
  aws ec2 describe-route-tables --route-table-ids "$rt_id" \
    --query 'RouteTables[0].Routes[*]' --output json | jq -c '.[]' | while read -r route; do
    cidr=$(echo "$route" | jq -r '.DestinationCidrBlock // .DestinationIpv6CidrBlock // "N/A"')
    target=$(echo "$route" | jq -r '.GatewayId // .NatGatewayId // .TransitGatewayId // .VpcPeeringConnectionId // .InstanceId // "local"')
    echo "$subnet_id,$subnet_name,$vpc_id,$az,$rt_id,$cidr,$target" >> aws_account_report.csv
  done
done

