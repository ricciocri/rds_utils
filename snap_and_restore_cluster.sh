#!/usr/local/bin/bash
AWS_ACCESS_KEY_ID="AKIAIR6NJ2QXGNO6XTOA"
AWS_SECRET_ACCESS_KEY="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"
AWS_DEFAULT_REGION="eu-west-1"
AWS_CLI="docker run --rm -it -v $(pwd):/aws -v $HOME/.aws/:/root/.aws -v $HOME/.ssh/:/root/.ssh -v $(pwd):/aws -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} mesosphere/aws-cli"


PARSED_OPTIONS=$(getopt -n "$0" -o h --long "clustername:,rprefix:,rpostfix:,instancename:,instancetype:"  -- "$@")
source $HOME/.bash_profile
while true;
do
  case "$1" in
    --clustername )
	  CLUSTER_NAME=$2
      shift 2;;
    --rprefix )
  	  RESTORE_PREFIX="$2-"
      shift 2;;
    --rpostfix )
      RESTORE_POSTFIX="-$2"
      shift 2;;
    --instancename )
	  INSTANCE_NAME=$2
	  shift 2;;
	--instancetype )
	  INSTANCE_TYPE=$2
	  shift 2;;
    -- )
      shift
      break;;
	* ) break ;;
  esac
done


SNAP_ID=${RESTORE_PREFIX}${CLUSTER_NAME}${RESTORE_POSTFIX}
RESTORE_CLUSTER_NAME=${RESTORE_PREFIX}${CLUSTER_NAME}${RESTORE_POSTFIX}
RESTORE_INSTANCE_NAME=${RESTORE_PREFIX}${INSTANCE_NAME}${RESTORE_POSTFIX}

# Creates RDS cluster snapshot if not exists
if [ $(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available" ]; then
	${AWS_CLI} rds  create-db-cluster-snapshot --db-cluster-snapshot-identifier=${SNAP_ID} --db-cluster-identifier=${CLUSTER_NAME}
	while [[ $(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available"
	 ]]; do
		sleep 2
	done
fi
echo "Snapshot ${SNAP_ID} is available"

ENGINE=$(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Engine' | tr -d '"')

# Creates cluster from snapshot
echo "Starting restore of ${RESTORE_CLUSTER_NAME} from ${SNAP_ID} with engine ${ENGINE}"
${AWS_CLI} rds restore-db-cluster-from-snapshot --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --snapshot-identifier=${SNAP_ID} --engine=${ENGINE}
# Adds instance to that cluster
${AWS_CLI} rds create-db-instance --db-instance-identifier=${RESTORE_INSTANCE_NAME} --db-instance-class=${INSTANCE_TYPE} --engine=${ENGINE} --db-cluster-identifier=${RESTORE_CLUSTER_NAME}
${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
echo "Cluster ${RESTORE_CLUSTER_NAME} is available"

# Customizes the cluster
DB_CLUSTER_PARAMETER_GROUP=$(${AWS_CLI} rds describe-db-clusters --db-cluster-identifier=${CLUSTER_NAME} | jq '.DBClusters[0].DBClusterParameterGroup' | tr -d '"')
SECURITY_GROUPS=$(${AWS_CLI} rds describe-db-clusters --db-cluster-identifier=${CLUSTER_NAME} | jq '.DBClusters[0].VpcSecurityGroups[].VpcSecurityGroupId')
echo ${AWS_CLI} rds modify-db-cluster --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --db-cluster-parameter-group-name=${DB_CLUSTER_PARAMETER_GROUP} --vpc-security-group-ids ${SECURITY_GROUPS} --apply-immediately
${AWS_CLI} rds modify-db-cluster --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --db-cluster-parameter-group-name=${DB_CLUSTER_PARAMETER_GROUP} --vpc-security-group-ids ${SECURITY_GROUPS} --apply-immediately
