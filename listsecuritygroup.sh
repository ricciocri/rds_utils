#!/bin/bash
# List the Group name of all the SecurityGroups

if [ "$1" == "-h" ]
then
	echo "This script print the name of all the SecurityGroups
Usage: $0"
	exit 0
fi
aws ec2 describe-security-groups | jq .SecurityGroups[].GroupName| tr -d \"
