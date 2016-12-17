#!/bin/bash
# List the name of all the clusters manages by the actual aws user

if [ "$1" == "-h" ]
then
	echo "This script print the name of all the RDS cluster managed by the actual user
Usage: $0"
	exit 0
fi
aws rds describe-db-clusters | jq .DBClusters[].DBClusterIdentifier | tr -d \"
