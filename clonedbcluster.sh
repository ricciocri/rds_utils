#!/usr/bin/env bash
#set -x
# This script create a clone of or SourceClusterName1 or SourceClusterName2 in NewClusterName with parameters of OldClusterName
# Accept this arguments:
# sourceclustername1, sourceclustername2, newclustername, oldclustername, instancetype, country, ksmkeyid, awsprofile
# add cli_pager= in profiles in .aws/config or .aws/credentials

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "sourceclustername1:,sourceclustername2:,newclustername:,oldclustername:,instancetype:,country:,ksmkeyid:,awsprofile:"  -- "$@")
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
    --sourceclustername1 )
		  SourceClusterName1=$2
      shift 2;;
    --sourceclustername2 )
		  SourceClusterName2=$2
      shift 2;;
    --newclustername )
  		NewClusterName=$2
      shift 2;;
    --oldclustername )
      OldClusterName=$2
      shift 2;;
    --instancetype )
      InstanceType=$2
      shift 2;;
    --country )
      Country=$2
      shift 2;;
    --ksmkeyid )
      KsmKeyId=$2
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

if [[ -z $SourceClusterName1 ]] || [[ -z $SourceClusterName2 ]] || [[ -z $NewClusterName ]] || [[ -z $InstanceType ]] || [[ -z $Country ]] || [[ -z $KsmKeyId ]] || [[ -z $AwsProfile ]]
then
	echo "This script clone RDS Aurora SourceClusterName1 or SourceClusterName2 (must be ARN if cross-account) into RDS Aurora NewClusterName with parameters from OldClusterName (optional), with tag Country, KMS key ID to encrypt and AWS PROFILE to use.

 Usage: $0 --sourceclustername1 SOURCECLUSTERNAME1 --sourceclustername2 SOURCECLUSTERNAME2 --newclustername NEWCLUSTERNAME --oldclustername OLDCLUSTERNAME --instancetype INSTANCETYPE --country COUNTRY --ksmkeyid KMSKEYID --awsprofile AWS_PROFILE

 examples:
 $0 --sourceclustername1 mycluster1 --sourceclustername2 mycluster2 --newclustername my-new-cluster --oldclustername my-old-cluster --instancetype db.t3.small --country italy --ksmkeyid xxxx-xxxx-xxxx --awsprofile dev
 "
	exit 1
fi

AwsCli="docker run --rm -i -v $(pwd):/aws -v $HOME/.aws/:/root/.aws -v $HOME/.ssh/:/root/.ssh -e AWS_PROFILE=${AwsProfile} amazon/aws-cli"

Today=$(TC=Europe/Rome date "+%Y-%m-%d")
Yesterday=$(TC=Europe/Rome date "+%Y-%m-%d" -d "-1 day")
ThreeDaysAgo=$(TC=Europe/Rome date "+%Y-%m-%d" -d "-3 day")

NewClusterNameWithDate="$NewClusterName-cluster-$Today"
NewInstanceName="$NewClusterName-instance-$Today-1"

# check if new cluster allready exists
ClusterExists=$(${AwsCli} rds describe-db-clusters --no-cli-pager | jq -r '.DBClusters[].DBClusterIdentifier'| grep ${NewClusterNameWithDate} -c)

if [ -z "$ClusterExists" ]
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable ClusterExists $ClusterExists is empty, EXIT."
  exit 1
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable ClusterExists $ClusterExists is not empty, continue ...."
  if (( ${ClusterExists} == 0 ))
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBCluster $NewClusterNameWithDate don't exists, continue creation..."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBCluster $NewClusterNameWithDate allready exists, EXIT."
    exit 1
  fi
fi

# check if today is Monday
WeekDay="$(TC=Europe/Rome date +%A)"
if [ "$WeekDay" = "Monday" ]
then
  # check if old cluster is a clone with date ThreeDaysAgo
  NotThreeDaysAgoFound=$(${AwsCli} rds describe-db-clusters --no-cli-pager | jq -r '.DBClusters[].DBClusterIdentifier' | grep ${OldClusterName} | grep ${ThreeDaysAgo} -c)
  if [ -z "$NotThreeDaysAgoFound" ]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable NotThreeDaysAgoFound $NotThreeDaysAgoFound is empty, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable NotThreeDaysAgoFound $NotThreeDaysAgoFound is not empty, continue ...."
    if (( ${NotThreeDaysAgoFound} == 0 ))
    then
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- Today is Monday and OldCluster $OldClusterName is not a clone."
      OldClusterNameWithDate=$OldClusterName
    	DeleteOldCluster=false
    else
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- Today is Monday and OldCluster $OldClusterName is a clone with date."
    	OldClusterNameWithDate="$OldClusterName-cluster-$ThreeDaysAgo"
    	DeleteOldCluster=true
    fi
  fi
else
  # check if old cluster is a clone with date Yesterday
  NotYesterdayFound=$(${AwsCli} rds describe-db-clusters --no-cli-pager | jq -r '.DBClusters[].DBClusterIdentifier' | grep ${OldClusterName} | grep ${Yesterday} -c)
  if [ -z "$NotYesterdayFound" ]
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable NotYesterdayFound $NotYesterdayFound is empty, EXIT."
    exit 1
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Variable NotYesterdayFound $NotYesterdayFound is not empty, continue ...."
    if (( ${NotYesterdayFound} == 0 ))
    then
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- Today is not Monday and OldCluster $OldClusterName is not a clone."
      OldClusterNameWithDate=$OldClusterName
    	DeleteOldCluster=false
    else
      echo "$(date +"%Y-%m-%d %H:%M:%S") -- Today is not Monday and OldCluster $OldClusterName is a clone with date."
    	OldClusterNameWithDate="$OldClusterName-cluster-$Yesterday"
    	DeleteOldCluster=true
    fi
  fi
fi

OldClusterDbSecurityGroup=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${OldClusterNameWithDate}| jq -r '.DBClusters[].VpcSecurityGroups[].VpcSecurityGroupId'|tr '\r\n' ' ')
OldClusterDbSubnetGroup=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${OldClusterNameWithDate}| jq -r '.DBClusters[].DBSubnetGroup')
OldClusterDbClusterParameterGroup=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${OldClusterNameWithDate}| jq -r '.DBClusters[].DBClusterParameterGroup')
OldClusterInstanceWriter=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${OldClusterNameWithDate}| jq -r '.DBClusters[].DBClusterMembers[] | select(.IsClusterWriter == true).DBInstanceIdentifier')
OldClusterInstanceArn=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${OldClusterInstanceWriter}| jq -r '.DBInstances[].DBInstanceArn')
AllTags=$(${AwsCli} rds list-tags-for-resource --no-cli-pager --resource-name ${OldClusterInstanceArn}| jq .TagList)

for CLUSTER in $SourceClusterName1 $SourceClusterName2; do
if
  ${AwsCli} rds restore-db-cluster-to-point-in-time \
  --db-cluster-identifier ${NewClusterNameWithDate} \
  --restore-type copy-on-write \
  --source-db-cluster-identifier ${CLUSTER} \
  --use-latest-restorable-time \
  --vpc-security-group-ids ${OldClusterDbSecurityGroup} \
  --db-subnet-group-name ${OldClusterDbSubnetGroup} \
  --db-cluster-parameter-group-name ${OldClusterDbClusterParameterGroup} \
  --enable-cloudwatch-logs-exports audit \
  --kms-key-id ${KsmKeyId} \
  --deletion-protection \
  --backtrack-window 0 \
  --no-cli-pager \
  --tags "${AllTags}" > error-create-cluster 2>&1
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Creation of DBCluster $NewClusterNameWithDate from Source DBCluster $CLUSTER started...."
  rm -f error-create-cluster
  break
else
  if grep -q "Cannot create more than one cross-account clone against a cluster in the same account" error-create-cluster
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBCluster clone of $CLUSTER allready exists in this account: $(<error-create-cluster)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- RETRY ...."
    rm -f error-create-cluster
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Creation of DBCluster $NewClusterNameWithDate FAILDED with error $(<error-create-cluster)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- EXIT."
    rm -f error-create-cluster
    exit 1
  fi
fi
done

# Wait until cluster is available
ClusterStatus=unknown
while [ "$ClusterStatus" != "available" ]; do
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Wait DBCluster creation ..."
	sleep 10
	ClusterStatus=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${NewClusterNameWithDate} | jq -r '.DBClusters[0].Status')
done

# Update Country Tag to new cluster
NewClusterNameWithDateArn=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${NewClusterNameWithDate}| jq -r '.DBClusters[].DBClusterArn')
if
	${AwsCli} rds add-tags-to-resource \
	--resource-name ${NewClusterNameWithDateArn} \
	--no-cli-pager \
	--tags "[{\"Key\": \"Country\",\"Value\": \"$Country\"}]"
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Update Tag Country to DBCluster $NewClusterNameWithDate finish."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Failed to create DBCluster $NewClusterNameWithDate, EXIT."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- Finish Creation of DBCluster $NewClusterNameWithDate."

# Retrive Parameter Group from old instance
OldClusterInstanceParameterGroup=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${OldClusterInstanceWriter}| jq -r '.DBInstances[].DBParameterGroups[].DBParameterGroupName')

# check if Instance allready exists
InstanceExists=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${NewInstanceName}| jq -r '.DBInstances[].DBInstanceIdentifier'| grep ${NewInstanceName} -c)

if (( ${InstanceExists} == 0 ))
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- DBInstance $NewInstanceName don't exists, creation continue ..."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: DBInstance $NewInstanceName allready exists, EXIT."
  exit 1
fi

# Create DB instance
if
	${AwsCli} rds create-db-instance \
	--db-instance-class ${InstanceType} \
	--engine aurora \
	--db-cluster-identifier ${NewClusterNameWithDate} \
	--db-instance-identifier ${NewInstanceName} \
	--publicly-accessible \
	--db-parameter-group-name ${OldClusterInstanceParameterGroup} \
  --auto-minor-version-upgrade \
	--no-cli-pager \
	--tags "${AllTags}" > /dev/null 2>&1
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Creation of DBInstance $NewInstanceName started...."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Failed to create DBInstance $NewInstanceName on DBCluster $NewClusterNameWithDate, EXIT."
  exit 1
fi

# wait until Instance is available
${AwsCli} rds wait db-instance-available --no-cli-pager --db-instance-identifier ${NewInstanceName}

InstanceStatus=unknown
while [ "$InstanceStatus" != "available" ]; do
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Wait DBInstances creation ..."
	sleep 1
	InstanceStatus=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${NewInstanceName} | jq -r '.DBInstances[].DBInstanceStatus')
done

# Set Country Tag to new Instance
NewInstanceArn=$(${AwsCli} rds describe-db-instances --no-cli-pager --db-instance-identifier ${NewInstanceName}| jq -r '.DBInstances[].DBInstanceArn')

if
	${AwsCli} rds add-tags-to-resource \
	--resource-name ${NewInstanceArn} \
	--no-cli-pager \
	--tags "[{\"Key\": \"Country\",\"Value\": \"$Country\"}]"
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Update Tag Country to DBInstance $NewInstanceName finish."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Failed to update Tag Country on DBInstance $NewInstanceName, EXIT."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- Finish Creation of DBInstance $NewInstanceName."

# Output
if [ ${ClusterStatus}  = "available" ] && [ "${InstanceStatus}" = "available" ]; then

	NewClusterEndpoint=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${NewClusterNameWithDate} |jq -r '.DBClusters[].Endpoint')
	OldClusterEndpoint=$(${AwsCli} rds describe-db-clusters --no-cli-pager --db-cluster-identifier ${OldClusterNameWithDate} |jq -r '.DBClusters[].Endpoint')

	cat << EOFF > vars-clonedbcluster
NewClusterEndpoint=${NewClusterEndpoint}
OldClusterEndpoint=${OldClusterEndpoint}
NewClusterName=${NewClusterNameWithDate}
OldClusterName=${OldClusterNameWithDate}
OldInstanceName=${OldClusterInstanceWriter}
DeleteOldCluster=${DeleteOldCluster}
EOFF
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- KO"
fi
