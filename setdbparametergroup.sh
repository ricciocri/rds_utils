#!/bin/bash -x
# Take as input the name of the RDS CLUSTER and list the name of all the instances

if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script print the name of the instancs of the given RDS CLUSTERNAME
Usage: $0 CLUSTERNAME
CLUSTERNAME it's the name of the RDS cluster"

	exit 1
fi

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

ChangeDBpargr()
{
	local myindex=$1
	if (( ${myindex} < 0 ))
	then
		echo $mytotal
		return 0
	fi
	MyStatus=$(aws rds modify-db-instance --db-parameter-group-name ${DBParameterGroupName} --db-instance-identifier ${members[$myindex]} |jq '.DBInstance.DBParameterGroups[0]')
  sleep 300
	MyDBGroup=$(echo ${MyStatus}|jq '.DBParameterGroupName'|tr -d \")
	MyDBReboot=$(echo ${MyStatus}|jq '.ParameterApplyStatus'|tr -d \")
  if [ ${MyDBGroup} != ${DBParameterGroupName} ]
	then
		echo "Failed to change parameter group"
	  exit 9
	fi
	if [ "${MyDBReboot}" != "in-sync" ]; then
	  echo "${members[$myindex]} needs a reboot"
    if [ "${Reboot}" == "yes" ]; then
      aws rds reboot-db-instance --db-instance-identifier ${members[$myindex]}
	  fi
	fi
	local_index=$(($myindex-1))
	ChangeDBpargr ${local_index}
}

source $(dirname $0)/config.sh

ClusterName=$1
DBParameterGroupName=$2
Reboot=$3

#Put in the array members all the DbInstance replica of given ClusterName
mapfile -t members < <(${mydir}/listclustermembers.sh $ClusterName)
membernumber=${#members[@]}
index=$(($membernumber-1))

ChangeDBpargr ${index}
