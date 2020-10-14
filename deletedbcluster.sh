#!/usr/bin/env bash
#set -x
# This script delete a Cluster
# Accept arguments:
# skipfinalsnapshot, awsprofile
# add cli_pager= in profiles in .aws/config or .aws/credentials

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "skipfinalsnapshot:,awsprofile:"  -- "$@")
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
    --skipfinalsnapshot )
		  SkipFinalSnapshot=$2
      shift 2;;
    --awsprofile )
      AwsProfile=$2
      shift 2;;
		-- )
      shift
      break;;
		* ) break ;;
  esac
done

VarsSourceFile="./vars-clonedbcluster"

if [[ -f "$VarsSourceFile" && -s "$VarsSourceFile" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile exist and not empty, OK"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile not exist or empty, EXIT"
    exit 1
fi

. ./vars-clonedbcluster

echo NewClusterEndpoint=${NewClusterEndpoint}
echo OldClusterEndpoint=${OldClusterEndpoint}
echo NewClusterName=${NewClusterName}
echo OldClusterName=${OldClusterName}
echo OldInstanceName=${OldInstanceName}
echo DeleteOldCluster=${DeleteOldCluster}

if [[ -z $SkipFinalSnapshot ]] || [[ -z $AwsProfile ]] || [[ -z $DeleteOldCluster ]] || [[ -z $OldClusterName ]] || [[ -z $OldInstanceName ]]
then
	echo "This script delete RDS Aurora Cluster with SkipFinalSnapshot true or false and AWS PROFILE to use.

 Usage: $0 --skipfinalsnapshot BOOL(true|false) --awsprofile AWS_PROFILE

 examples:
 $0 --skipfinalsnapshot false --awsprofile dev
 "
	exit 1
fi

AwsCli="docker run --rm -i -v $(pwd):/aws -v $HOME/.aws/:/root/.aws -v $HOME/.ssh/:/root/.ssh -e AWS_PROFILE=${AwsProfile} amazon/aws-cli"

if [[ "$DeleteOldCluster" == "false" ]]
then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBCluster $OldClusterName don't need to be deleted, EXIT."
    rm -f vars-clonedbcluster
    exit 1
fi

if [[ "$DeleteOldCluster" == "true" ]]
then

  # check if Cluster exists
  ClusterExists=$(${AwsCli} rds describe-db-clusters --no-cli-pager | jq -r '.DBClusters[].DBClusterIdentifier'| grep ${OldClusterName} -c)

  if (( ${ClusterExists} == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBCluster $OldClusterName don't exists, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete DBCluster $OldClusterName in progress ..."
  fi

  # check if Instance exists
  InstanceExists=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${OldInstanceName}| jq -r '.DBInstances[].DBInstanceIdentifier'| grep ${OldInstanceName} -c)

  if (( ${InstanceExists} == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBInstance $OldInstanceName don't exists, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete DBInstance $OldInstanceName in progress ..."
  fi

  if [[ "$SkipFinalSnapshot" == "true" ]]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- with --skip-final-snapshot True ..."
    SkipFinalSnapshotArg="--skip-final-snapshot"
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- with --skip-final-snapshot False, set  final-db-snapshot-identifier=$OldClusterName-final-snapshot ..."
    SkipFinalSnapshotArg="--no-skip-final-snapshot --final-db-snapshot-identifier $OldClusterName-final-snapshot"
  fi

  # remove delete-protection
  if
  	${AwsCli} rds modify-db-cluster \
  	--db-cluster-identifier ${OldClusterName} \
  	--no-cli-pager \
  	--no-deletion-protection
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Remove deletion-protection on DBCluster $OldClusterName, DONE."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in remove deletion-protection on DBCluster $OldClusterName, EXIT."
    exit 1
  fi

  # delete Instance
  if
  	${AwsCli} rds delete-db-instance \
  	--db-instance-identifier ${OldInstanceName} \
  	--no-cli-pager
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete of DBInstance $OldInstanceName DONE."
    sleep 5
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in delete of DBInstance $OldInstanceName, EXIT."
    exit 1
  fi

  # delete cluster
  if
  	${AwsCli} rds delete-db-cluster \
  	--db-cluster-identifier ${OldClusterName} \
  	--no-cli-pager \
  	$SkipFinalSnapshotArg
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete of DBCluster $OldClusterName with $SkipFinalSnapshotArg DONE."
    rm -f vars-clonedbcluster
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in delete of DBCluster $OldClusterName with $SkipFinalSnapshotArg, EXIT."
    exit 1
  fi

fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
