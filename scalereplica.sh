#!/bin/bash -x
# This script scale the number of readers instances for CLUSTERNAME to DESIREDINSTANCENUMBER
# it scales both up and down and bring the total number of readers to DESIREDINSTANCENUMBER
# This script don't touch the writer instance

source $(dirname $0)/config.sh
if [ -z "$1" ] || [ "$1" == "-h" ] || [ -z "$2" ]
then
	echo "This script scale the number of readers instances for CLUSTERNAME to DESIREDINSTANCENUMBER
	it scales both up and down and bring the total number of readers to DESIREDINSTANCENUMBER
	if OPTIONALCONTACT is provided it will set up a check on the CPUutilization of the DBInstance/s created
Usage: $0 CLUSTERNAME DESIREDINSTANCENUMBER OPTIONALCONTACT
examples:

$0 myaurora-cluster 3 <-- This bring the total number of readers to 3
$0 myaurora-cluster 0  <-- This delete all the instances of type reader
$0 myaurora-cluster 3 arn:aws:sns:eu-west-1:8281216198:mycontact  <-- This bring the total number of readers to 3 and for each set a Cloudwatch alarm

"
	exit 1
fi

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

ClusterName=$1
DesiredInstances=$2
Contact=$3

ScaleRDS()
{
	local_replica=$1
	local_desired=$2
  if (( $local_replica == $local_desired ))
  then
    return 0
  elif  (( $local_replica > $local_desired ))
	then
		echo "Scale down ${ClusterName}"
		index=$(($local_replica-1))
		aws rds delete-db-instance --db-instance-identifier ${readers[$index]}
		aws cloudwatch delete-alarms --alarm-name HIGH-CPU-${readers[$index]}
		if [ "${writerclass}" == "db.t2.medium" ]
		then
			aws cloudwatch delete-alarms --alarm-name LOW-CPUCREDIT-${ClusterName}-${newtotal}
		fi
    aws rds wait db-instance-deleted --db-instance-identifier ${readers[$index]}
		ScaleRDS $index $local_desired
  else
 		echo "Scale up ${ClusterName}"
		newtotal=$((${local_replica}+1))
		realtotal=${newtotal}
		notfound=$(${mydir}/showinstanceprop.sh ${ClusterName}-${newtotal} 2>&1 |grep DBInstanceNotFound -c)
		if (( ${notfound} == 0 ))
		then
		  newtotal=${newtotal}${newtotal}
		fi
		if ${writerpublic}
		then
		  aws rds create-db-instance --db-instance-identifier ${ClusterName}-${newtotal} --db-cluster-identifier ${ClusterName} --db-instance-class ${writerclass} --db-parameter-group-name ${writerpamgroup} --publicly-accessible --engine aurora --tags "${writertags}"
    else
			aws rds create-db-instance --db-instance-identifier ${ClusterName}-${newtotal} --db-cluster-identifier ${ClusterName} --db-instance-class ${writerclass} --db-parameter-group-name ${writerpamgroup} --no-publicly-accessible --engine aurora --tags "${writertags}"
    fi
		if [ ! -z "$Contact" ]
		then
	  	aws cloudwatch put-metric-alarm --alarm-name HIGH-CPU-${ClusterName}-${newtotal} --alarm-description "Alarm when CPU exceeds 85 percent" --metric-name CPUUtilization --namespace AWS/RDS --statistic Average --period 300 --threshold 85 --comparison-operator GreaterThanThreshold  --dimensions "Name=DBInstanceIdentifier,Value=${ClusterName}-${newtotal}" --evaluation-periods 3 --alarm-actions ${Contact} --unit Percent
      if [ "${writerclass}" == "db.t2.medium" ]
			then
				aws cloudwatch put-metric-alarm --alarm-name LOW-CPUCREDIT-${ClusterName}-${newtotal} --alarm-description "Alarm when CPU credits it's less than 60" --metric-name CPUCreditBalance --namespace AWS/RDS --statistic Average --period 300 --threshold 60 --comparison-operator LessThanOrEqualToThreshold  --dimensions "Name=DBInstanceIdentifier,Value=${ClusterName}-${newtotal}" --evaluation-periods 3 --alarm-actions ${Contact}
      fi
		fi
		aws rds wait db-instance-available --db-instance-identifier ${ClusterName}-${newtotal}
		newtotal=${realtotal}
		ScaleRDS $newtotal $local_desired
	fi
}
#Put in the array readers all the DbInstance replica of given ClusterName
mapfile -t readers < <(${mydir}/listclusterreader.sh $ClusterName)

#Get the writer instance info
writer=$(${mydir}/listclusterwriter.sh $ClusterName)
writerarn=$(${mydir}/showinstanceprop.sh ${writer} DBInstanceArn)
writerclass=$(${mydir}/showinstanceprop.sh ${writer} DBInstanceClass)
writerpamgroup=$(${mydir}/showinstanceprop.sh ${writer} DBParameterGroups[].DBParameterGroupName)
writertags=$(${mydir}/gettags.sh ${writerarn}| jq .TagList| jq 'del(.[]| select(.Key == "aws:cloudformation:logical-id"))|del(.[]|select(.Key == "aws:cloudformation:stack-id"))|del(.[]|select(.Key == "aws:cloudformation:stack-name"))'
writerpublic=$(${mydir}/showinstanceprop.sh ${writer} PubliclyAccessible)

#Get the actual number of readers before applying the changes.
replicanumber=${#readers[@]}
ScaleRDS $replicanumber $DesiredInstances

#Check if the final result is what we expect
mapfile -t readers_final < <(${mydir}/listclusterreader.sh $ClusterName)
replicafinalnumber=${#readers_final[@]}
if (( $replicafinalnumber == $DesiredInstances ))
then
	exit 0
else
	exit 99
fi
