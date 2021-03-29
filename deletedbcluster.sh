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
echo NewClusterReaderEndpoint=${NewClusterReaderEndpoint}
echo OldClusterEndpoint=${OldClusterEndpoint}
echo NewClusterName=${NewClusterName}
echo OldClusterName=${OldClusterName}
echo OldInstanceWriterName=${OldInstanceWriterName}
echo OldInstanceReaderName=${OldInstanceReaderName}
echo DeleteOldCluster=${DeleteOldCluster}
echo AddReadReplica=${AddReadReplica}

if [[ -z $SkipFinalSnapshot ]] || [[ -z $AwsProfile ]] || [[ -z $DeleteOldCluster ]] || [[ -z $OldClusterName ]] || [[ -z $OldInstanceWriterName ]]
then
	echo "This script delete RDS Aurora Cluster with SkipFinalSnapshot true or false and AWS PROFILE to use.

 Usage: $0 --skipfinalsnapshot BOOL(true|false) --awsprofile AWS_PROFILE

 examples:
 $0 --skipfinalsnapshot false --awsprofile dev
 "
	exit 1
fi

if [ "$DeleteOldCluster"  = "true" ] || [ "$DeleteOldCluster" = "false" ]; then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- DeleteOldCluster is true or false, continue ..."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- DeleteOldCluster must be true or false, EXIT"
  exit 1
fi

AwsCli="docker run --rm -i -v $(pwd):/aws -v $HOME/.aws/:/root/.aws -v $HOME/.ssh/:/root/.ssh -e AWS_PROFILE=${AwsProfile} amazon/aws-cli"



if [[ "$DeleteOldCluster" == "false" ]]
then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBCluster $OldClusterName don't need to be deleted, EXIT."
    rm -f vars-clonedbcluster
    exit 0
fi

if [[ "$DeleteOldCluster" == "true" ]]
then
  # check if DB Snapshot exists and delete it
  SevenDaysAgo=$(TC=Europe/Rome date "+%Y-%m-%d" -d "-7 day")
  OldClusterNameWithoutDate=$(echo $OldClusterName | sed 's/-[0-9]\+-[0-9]\+-[0-9]\+$//')
  SnapshotToDelete="$OldClusterNameWithoutDate$SevenDaysAgo-final-snapshot"
  SnapshotExists=$(${AwsCli} rds describe-db-cluster-snapshots --no-cli-pager --snapshot-type manual | jq -r '.DBClusterSnapshots[].DBClusterSnapshotIdentifier' | grep ${SnapshotToDelete} -c)

  if (( SnapshotExists == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBCluster Snapshot $SnapshotToDelete don't exists, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete DBCluster Snapshot $SnapshotToDelete in progress ..."
    ${AwsCli} rds delete-db-cluster-snapshot \
    --db-cluster-snapshot-identifier $SnapshotToDelete \
    --no-cli-pager
  fi

  # check if Cluster exists
  ClusterExists=$(${AwsCli} rds describe-db-clusters --no-cli-pager | jq -r '.DBClusters[].DBClusterIdentifier'| grep ${OldClusterName} -c)

  if (( ClusterExists == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBCluster $OldClusterName don't exists, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete DBCluster $OldClusterName in progress ..."
  fi

  # check if Instance Writer exists
  InstanceWriterExists=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${OldInstanceWriterName}| jq -r '.DBInstances[].DBInstanceIdentifier'| grep ${OldInstanceWriterName} -c)
  if (( InstanceWriterExists == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Writer DBInstance $OldInstanceWriterName don't exists, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Writer DBInstance $OldInstanceWriterName will be deleted ..."
  fi

  # check if Instance Reader exists
  if [ -z "${OldInstanceReaderName}" ]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- OldInstanceReaderName don't exists"
  else
    for OldInstanceReaderName1 in ${OldInstanceReaderName}
    do
      InstanceReaderExists=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier $OldInstanceReaderName1| jq -r '.DBInstances[].DBInstanceIdentifier'| grep $OldInstanceReaderName1 -c)
      if (( InstanceReaderExists == 0 ))
      then
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Reader DBInstance $OldInstanceReaderName1 don't exists, EXIT."
        exit 1
      else
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- Reader DBInstance $OldInstanceReaderName1 will be deleted ..."
      fi
    done  
  fi

  if [[ "$SkipFinalSnapshot" == "true" ]]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- with --skip-final-snapshot True ..."
    SkipFinalSnapshotArg="--skip-final-snapshot"
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- with --skip-final-snapshot False, set final-db-snapshot-identifier=$OldClusterName-final-snapshot ..."
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

  # delete Instance Reader and Scaling Policy if exists
  if [ -z "${OldInstanceReaderName}" ]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- OldInstanceReaderName don't exists and don't delete"
  else
    for OldInstanceReaderName2 in ${OldInstanceReaderName}
    do
      if
        ${AwsCli} rds delete-db-instance \
        --db-instance-identifier $OldInstanceReaderName2 \
        --no-cli-pager
      then
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete of Reader DBInstance $OldInstanceReaderName2 DONE."
        sleep 5
      else
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in delete of Reader DBInstance $OldInstanceReaderName2, EXIT."
        exit 1
      fi
    done

    # Delete scaling policy
    PolicyExists=$(${AwsCli} application-autoscaling describe-scaling-policies --no-cli-pager --service-namespace rds --policy-names rds-stg-autoscale-policy --resource-id cluster:${OldClusterName} | jq -r '.ScalingPolicies[].ResourceId'| grep ${OldClusterName} -c)
    if (( PolicyExists == 1 ))
    then
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- Scaling Policy exists on DBCluster $OldClusterName, delete it ..."
      if
        ${AwsCli} application-autoscaling delete-scaling-policy --no-cli-pager \
        --policy-name rds-stg-autoscale-policy --service-namespace rds \
        --resource-id cluster:${OldClusterName} --scalable-dimension rds:cluster:ReadReplicaCount
      then
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete Scaling Policy of DBCluster $OldClusterName DONE."
      else
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in Delete Scaling Policy of DBCluster $OldClusterName."
      fi  
    fi

    # Deregister Scalable Target
    ClusterRegistered=$(${AwsCli} application-autoscaling describe-scalable-targets --no-cli-pager --service-namespace rds --resource-id cluster:${OldClusterName} | jq -r '.ScalableTargets[].ResourceId'| grep ${OldClusterName} -c)
    if (( ClusterRegistered == 1 ))
    then
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBCluster $OldClusterName is registered, deregister it ..."
      if
        ${AwsCli} application-autoscaling deregister-scalable-target --no-cli-pager \
        --service-namespace rds --resource-id cluster:${OldClusterName} --scalable-dimension rds:cluster:ReadReplicaCount
      then
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- Deregister of DBCluster $OldClusterName DONE."
      else
        echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in Deregister of DBCluster $OldClusterName."
      fi  
    fi
  fi

  # delete Writer Instance
  if
  	${AwsCli} rds delete-db-instance \
  	--db-instance-identifier "${OldInstanceWriterName}" \
  	--no-cli-pager
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Delete of Writer DBInstance $OldInstanceWriterName DONE."
    sleep 5
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: in delete of Writer DBInstance $OldInstanceWriterName, EXIT."
    exit 1
  fi

  # delete Cluster
  if
  	${AwsCli} rds delete-db-cluster \
  	--db-cluster-identifier "${OldClusterName}" \
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
