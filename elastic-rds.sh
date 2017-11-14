#!/usr/bin/env bash
set -x
# This script scale the number of readers instances for CLUSTERNAME to DESIREDINSTANCENUMBER
# it scales both up and down and bring the total number of readers to DESIREDINSTANCENUMBER
# This script don't touch the writer instance

source "$(dirname $0)/config.sh"
MinCPU=75
MaxCPU=20
Statistics=Average
StatisticsMin=Average

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "clustername:,mininst:,maxinst:,CpuLow:,CpuHigh:,Latency:,mail:"  -- "$@")
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
    --clustername )
		  ClusterName=$2
      shift 2;;
    --mininst )
  		MinInstances=$2
      shift 2;;
    --maxinst )
      MaxInstances=$2
      shift 2;;
    --CpuLow )
		  MaxCPU=$2
			shift 2;;
		--CpuHigh )
			MinCPU=$2
			shift 2;;
		--Latency )
			MaxLatency=$2
			shift 2;;
    --mail )
			mail=$2
			shift 2;;
		-- )
      shift
      break;;
		* ) break ;;
  esac
done

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

if [[ -z $ClusterName ]] || [[ -z $MinInstances ]] || [[ -z $MaxInstances ]]
then
	echo "This script scale automatically scale the number of readers instances for CLUSTERNAME down by 1 down to MINNUMBER if the average CpuUtilization of all the readers is under CPULOW (default to 20%) or up by 1 up to MAXNUMBER if the average CpuUtilization of all the readers is above CPUHIGH (default to 75%) with the flag LATENCY set it also do a scale up if it detects a latency over LATENCY	MilliSeconds on any reader.

 Usage: $0 --clustername CLUSTERNAME --mininst MINNUMBER --maxinst MAXNUMBER [ --CpuLow CPULOW --CpuHigh CPUHIGH --Latency LATENCY--mail MAIL]

 examples:
 $0 myaurora-cluster --clustername mycluster --mininst 1 --maxinst 3 <-- This automatically scale automatically down to 1 or up to 3
 "
	exit 1
fi

NOW=$(TZ=UTC date "+%Y-%m-%dT%H:%M:%SZ")
BEFORE=$(TZ=UTC date "+%Y-%m-%dT%H:%M:%SZ" -d "-5 minutes")

CheckLatency()
{
  local myindex=$1
	if (( ${myindex} < 0 ))
	then
		return 0
	fi
	LatencyFloat=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name SelectLatency --start-time ${BEFORE} --end-time ${NOW} --period 300 --statistics ${Statistics} --dimensions "Name=DBInstanceIdentifier,Value=${readers[$myindex]}"| jq .Datapoints[].${Statistics})
  latency=${LatencyFloat%.*}
	if (( ${latency} > ${MaxLatency} ))
  then
		echo "Scale up ${ClusterName}"
		if [ ! -z ${mail+x} ]
		  then
		  mail -s "$ClusterName has ${latency} ms latency on Select, Scale It Up!" ${mail} < /dev/null
    fi
	fi
	local_index=$(($myindex-1))
  CheckLatency ${local_index}
}

CheckCpu()
{
	local myindex=$1
	local mytotal=$2
	if (( ${myindex} < 0 ))
	then
		echo $mytotal
		return 0
	fi
	CpuFloat=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name CPUUtilization --start-time ${BEFORE} --end-time ${NOW} --period 300 --statistics ${StatisticsMin} --dimensions "Name=DBInstanceIdentifier,Value=${readers[$myindex]}"| jq .Datapoints[].${StatisticsMin})
  CpuUtilization=${CpuFloat%.*}
	if [ ! -z "${CpuUtilization}" ]
	then
	  mysum=$((${mytotal}+${CpuUtilization}))
  else
    mysum=${mytotal}
	fi
	local_index=$(($myindex-1))
  CheckCpu ${local_index} ${mysum}
}

#Put in the array readers all the DbInstance replica of given ClusterName
mapfile -t readers < <(${mydir}/listclusterreader.sh $ClusterName)

#Get the writer instance info
writer=$(${mydir}/listclusterwriter.sh $ClusterName)

#Get the actual number of readers before applying the changes.
replicanumber=${#readers[@]}
index=$(($replicanumber-1))

#Check if something is ongoing on the last instance
if [ $(${mydir}/showinstanceprop.sh ${readers[$index]} DBInstanceStatus) != "available" ]
then
	echo "Exit for ongoing operation on instance ${readers[$index]} "
	exit 0
fi

cputotal=$(CheckCpu ${index} 0)
#	average=$(echo "scale=2 ; ${cputotal} / $index" | bc)
if (( ${replicanumber} > 1 ))
  then
    averagemax=$(( ${cputotal} / $index ))
	else
		averagemax=$(( ${cputotal} / ${replicanumber} ))
fi
averagemin=$(( ${cputotal} / ${replicanumber} ))

#Scale down the number of instances if needed
if (( ${replicanumber} > ${MinInstances} ))
then
	if (( ${averagemax} < ${MaxCPU} ))
  then
		echo "Scale Down ${ClusterName}"
		if [ ! -z ${mail+x} ]
		  then
			mail -s "$ClusterName has an average of ${averagemax} CPU usage on ${replicanumber} Replicas, Scaling It Down!" ${mail} < /dev/null
    fi
		$(${mydir}/scalereplica.sh ${ClusterName} ${index} arn:aws:sns:eu-west-1:828142006918:monitor ) > /dev/null
		sleep 180
		exit 0
  fi
fi

#Scale up the number of instances if needed
if (( ${replicanumber} < ${MaxInstances} ))
then
	if [ ! -z ${MaxLatency+x} ]
		then
  CheckLatency ${index}
  fi
	if (( ${averagemin} > ${MinCPU} ))
  then
		echo "Scale Up ${ClusterName}"
		if [ ! -z ${mail+x} ]
		  then
			mail -s "$ClusterName has an average of ${averagemin} CPU usage on ${replicanumber} Replicas, Scaling It up!" ${mail} < /dev/null
    fi
    newreplica=$(($replicanumber+1))
		$(${mydir}/scalereplica.sh ${ClusterName} ${newreplica} arn:aws:sns:eu-west-1:828142006918:monitor ) > /dev/null
		sleep 180
		exit 0
  fi
fi

echo "Nothing to Scale"
exit 0
