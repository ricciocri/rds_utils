#!/bin/bash
# Show the value of 1 particular key
# Default to arn if second parameter is not provided
source $(dirname $0)/config.sh
if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script Show the value of 1 particular key, default to arn if second parameter is not provided
Usage: $0 DBINSTANCENAME PROPERTY
examples:

$0 myaurora DBInstanceClass <-- This print the Instance class of the DBInstance myaurora
$0 myaurora                 <-- This print the ARN of the DBInstance myaurora
"
	exit 1
fi

if [ -z "$2" ]
then
	aws rds describe-db-instances --db-instance-identifier $1 | jq .DBInstances[].DBInstanceArn | tr -d \"
else
	aws rds describe-db-instances --db-instance-identifier $1 | jq .DBInstances[].$2 | tr -d \"
fi
