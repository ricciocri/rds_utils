#!/bin/bash
CLUSTER_NAME=$1
RESTORE_PREFIX=$2
RESTORE_POSTFIX=$3


SNAP_ID=${CLUSTER_NAME}-${RESTORE_POSTFIX}
RESTORE_NAME=${RESTORE_PREFIX}-${CLUSTER_NAME}-${RESTORE_POSTFIX}

# Creates RDS cluster snapshot if not exists
if [ $(aws rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available" ]; then
	aws rds  create-db-cluster-snapshot --db-cluster-snapshot-identifier=${SNAP_ID} --db-cluster-identifier=${CLUSTER_NAME}
	while [[ $(aws rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available"
	 ]]; do
		sleep 2
	done
fi
echo "Snapshot ${SNAP_ID} is available"


ENGINE=$(aws rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Engine' | tr -d '"')
echo "Starging restore of ${RESTORE_NAME} from ${SNAP_ID} with engine ${ENGINE}"
aws rds restore-db-cluster-from-snapshot --db-cluster-identifier=${RESTORE_NAME} --snapshot-identifier=${SNAP_ID} --engine=${ENGINE}