#!/usr/bin/env bash
# Take as input the name of the RDS CLUSTER and clone all tha amazon tags
# associated to the writer instance to all the readers

source $(dirname $0)/config.sh
if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script copy all the Amazon Tags from the writer instance to all the readers
Usage: $0 CLUSTERNAME
CLUSTERNAME it's the name of the RDS cluster"

	exit 1
fi

CLUSTER=$1

writer=$(${mydir}/listclusterwriter.sh $CLUSTER)
writerarn=$(${mydir}/showinstanceprop.sh ${writer} DBInstanceArn)
for INSTANCE in $(${mydir}/listclusterreader.sh $CLUSTER); do
	readerarn=$(${mydir}/showinstanceprop.sh ${INSTANCE} DBInstanceArn)
	${mydir}/copytags.sh $writerarn $readerarn
	echo "Added tags to ${INSTANCE}"
done
