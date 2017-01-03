#!/bin/bash
# Take as input the name of the RDS CLUSTER and list the name of the readers instance

if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script print the name of the readers instance of the given RDS CLUSTERNAME
Usage: $0 CLUSTERNAME
CLUSTERNAME it's the name of the RDS cluster"

	exit 1
fi
aws rds describe-db-clusters --db-cluster-identifier $1 | jq '.DBClusters[].DBClusterMembers[] | select(.IsClusterWriter == false) | .DBInstanceIdentifier' | tr -d \" | sort -V
