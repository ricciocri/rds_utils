#!/usr/bin/env bash
if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

AWS_CLI="docker run --rm -it -v $(pwd):/aws -v $HOME/.aws/:/root/.aws -v $HOME/.ssh/:/root/.ssh -v $(pwd):/aws -e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} mesosphere/aws-cli"

NEEDED_ENV="AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION"

if [ -z ${AWS_ACCESS_KEY_ID} ]; then echo "AWS_ACCESS_KEY_ID is unset."; ENVERROR=true; fi
if [ -z ${AWS_SECRET_ACCESS_KEY} ]; then echo "AWS_SECRET_ACCESS_KEY is unset"; ENVERROR=true; fi
if [ -z ${AWS_DEFAULT_REGION} ]; then echo "AWS_DEFAULT_REGION is unset"; ENVERROR=true; fi

if [ $ENVERROR ]; then
	echo "Please add to your environment the following variables: ${NEEDED_ENV}"; exit 1;
fi

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


SNAP_ID=${RESTORE_PREFIX}${CLUSTER_NAME}${RESTORE_POSTFIX}-$(date +"%m-%d-%y-%H-%M-%S")
RESTORE_CLUSTER_NAME=${RESTORE_PREFIX}${CLUSTER_NAME}${RESTORE_POSTFIX}
RESTORE_INSTANCE_NAME=${RESTORE_PREFIX}${INSTANCE_NAME}${RESTORE_POSTFIX}
SOURCE_INSTANCE_NAME=${INSTANCE_NAME}

# Creates RDS cluster snapshot if not exists
if [ $(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available" ]; then
	${AWS_CLI} rds  create-db-cluster-snapshot --db-cluster-snapshot-identifier=${SNAP_ID} --db-cluster-identifier=${CLUSTER_NAME}
	while [[ $(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Status' | tr -d '"') != "available"
	 ]]; do
		sleep 2
	done
fi
echo $(date) - "Snapshot ${SNAP_ID} is available"

ENGINE=$(${AWS_CLI} rds describe-db-cluster-snapshots --db-cluster-identifier=${CLUSTER_NAME} --snapshot-type=manual --db-cluster-snapshot-identifier=${SNAP_ID} | jq '.DBClusterSnapshots[0].Engine' | tr -d '"')

# Creates cluster from snapshot
echo $(date) - "Starting restore of ${RESTORE_CLUSTER_NAME} from ${SNAP_ID} with engine ${ENGINE}"
${AWS_CLI} rds restore-db-cluster-from-snapshot --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --snapshot-identifier=${SNAP_ID} --engine=${ENGINE}
# Adds instance to that cluster
${AWS_CLI} rds create-db-instance --db-instance-identifier=${RESTORE_INSTANCE_NAME} --db-instance-class=${INSTANCE_TYPE} --engine=${ENGINE} --db-cluster-identifier=${RESTORE_CLUSTER_NAME}

# wait instance available
while [ "${exit_status}" != "0" ]
do
  ${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
  exit_status="$?"
done
echo $(date) - "Cluster ${RESTORE_CLUSTER_NAME} is available for customization"

# Customizes the cluster
DB_CLUSTER_PARAMETER_GROUP=$(${AWS_CLI} rds describe-db-clusters --db-cluster-identifier=${CLUSTER_NAME} | jq '.DBClusters[0].DBClusterParameterGroup' | tr -d '"')
SECURITY_GROUPS=$(${AWS_CLI} rds describe-db-clusters --db-cluster-identifier=${CLUSTER_NAME} | jq '.DBClusters[0].VpcSecurityGroups[].VpcSecurityGroupId')
DB_PARAMETER_GROUP=$(${AWS_CLI} rds describe-db-instances --db-instance-identifier=${SOURCE_INSTANCE_NAME} | jq '.DBInstances[0].DBParameterGroups[].DBParameterGroupName'| tr -d '"')

# SET instance publicly accessible and parameter-group
${AWS_CLI} rds modify-db-instance --db-instance-identifier=${RESTORE_INSTANCE_NAME} --db-parameter-group-name=${DB_PARAMETER_GROUP} --publicly-accessible --apply-immediately
sleep 10

# wait instance available
while [ "${exit_status}" != "0" ]
do
  ${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
  exit_status="$?"
done

# wait instance available
while [ "${exit_status}" != "0" ]
do
  ${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
  exit_status="$?"
done

echo $(date) - ${AWS_CLI} rds modify-db-cluster --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --db-cluster-parameter-group-name=${DB_CLUSTER_PARAMETER_GROUP} --vpc-security-group-ids ${SECURITY_GROUPS} --apply-immediately
# TODO fix here, fail with docker
${AWS_CLI} rds modify-db-cluster --db-cluster-identifier=${RESTORE_CLUSTER_NAME} --db-cluster-parameter-group-name=${DB_CLUSTER_PARAMETER_GROUP} --vpc-security-group-ids ${SECURITY_GROUPS} --apply-immediately
sleep 10

# wait instance available
while [ "${exit_status}" != "0" ]
do
  ${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
  exit_status="$?"
done

# reboot
echo $(date) - ${AWS_CLI} rds reboot-db-instance --db-instance-identifier=${RESTORE_INSTANCE_NAME}
${AWS_CLI} rds reboot-db-instance --db-instance-identifier=${RESTORE_INSTANCE_NAME}
sleep 10

# wait instance available
while [ "${exit_status}" != "0" ]
do
  ${AWS_CLI} rds wait db-instance-available --db-instance-identifier=${RESTORE_INSTANCE_NAME}
  exit_status="$?"
done

echo $(date) - "Cluster ${RESTORE_CLUSTER_NAME} is available"
