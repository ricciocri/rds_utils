#!/bin/bash
# Take as input the name of the RDS CLUSTER and reboot all the readers instances
# it reboots 1 instance at time and wait that the instance it's available before moving on the next

source $(dirname $0)/config.sh
if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script reboot all the readers instances of the given RDS CLUSTERNAME
it reboots 1 instance at time and wait that the instance it's available before moving on the next
Usage: $0 CLUSTERNAME
CLUSTERNAME it's the name of the RDS cluster"

	exit 1
fi
CLUSTER=$1

for INSTANCE in $(${mydir}/listclusterreader.sh $CLUSTER); do
	echo "Reboot instance ${INSTANCE}"
	aws rds reboot-db-instance --db-instance-identifier $INSTANCE > /dev/null
	aws rds wait db-instance-available --db-instance-identifier $INSTANCE > /dev/null
done
