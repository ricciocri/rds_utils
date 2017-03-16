#!/bin/bash
# List the TAGS of target ARN resource

source "$(dirname $0)/config.sh"

if [ -z "$1" ] || [ "$1" == "-h" ]
then
	echo "This script print  all the dbinstances that need a reboot for applying a change in Group Parameter
Usage: $0 ARNRESOURCE
ARNRESOURCE it's the ARN of the resource"
	exit 0
fi
aws rds list-tags-for-resource --resource-name "$1"
