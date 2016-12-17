#!/bin/bash
# Take as input source ARN and the destination arn
# Copy all the amazon TAGS from Source to Destination

source $(dirname $0)/config.sh
if [ -z "$1" ] || [ "$1" == "-h" ] || [ -z "$2" ]
then
	echo "This script copy all the amazon TAGS from SOURCEARN to DESTINATIONARN
Usage: $0 SOURCEARN DESTINATIONARN
"
	exit 1
fi

sourcearn=$1
destinationarn=$2

alltags=$(${mydir}/gettags.sh $1 | jq .TagList)
aws rds add-tags-to-resource --resource-name $2 --tags "${alltags}"
