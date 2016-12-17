#!/bin/bash
# List the name of all the dbinstances that need a reboot for applying a change in Group Parameter

source $(dirname $0)/config.sh

if [ "$1" == "-h" ]
then
	echo "This script print  all the dbinstances that need a reboot for applying a change in Group Parameter
Usage: $0"
	exit 0
fi
for CLUSTER in $(${mydir}/listcluster.sh); do
	for INSTANCE in $(${mydir}/listclustermembers.sh $CLUSTER); do
		STATUS=$(${mydir}/showinstanceprop.sh $INSTANCE DBParameterGroups[].ParameterApplyStatus)
		echo ${INSTANCE}: ${STATUS}
	done
done
