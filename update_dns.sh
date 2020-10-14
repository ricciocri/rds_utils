#!/usr/bin/env bash
#set -x
# This script update a DNS record
# https://dnsmadeeasy.com/pdf/API-Docv2.pdf

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "domainid:,recordname:,recordtype:,recordttl:,apikey:,secretkey:"  -- "$@")
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
    --domainid )
		  DomainId=$2
      shift 2;;
    --recordname )
  	  RecordName=$2
  	  shift 2;;
  	--recordtype )
  	  RecordType=$2
  	  shift 2;;
  	--recordttl )
  	  RecordTtl=$2
  	  shift 2;;
  	--apikey )
  	  ApiKey=$2
  	  shift 2;;
  	--secretkey )
  	  SecretKey=$2
  	  shift 2;;
		-- )
      shift
      break;;
		* ) break ;;
  esac
done


DnsMeApiPerl="./dnsmeapi.pl"

if [[ -f "$DnsMeApiPerl" && -s "$DnsMeApiPerl" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Perl script $DnsMeApiPerl exist and not empty, OK."
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Perl script $DnsMeApiPerl not exist or empty, EXIT."
    exit 1
fi

VarsSourceFile="./vars-clonedbcluster"

if [[ -f "$VarsSourceFile" && -s "$VarsSourceFile" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile exist and not empty, OK."
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile not exist or empty, EXIT."
    exit 1
fi

. ./vars-clonedbcluster

echo NewClusterEndpoint=${NewClusterEndpoint}
echo OldClusterEndpoint=${OldClusterEndpoint}
echo NewClusterName=${NewClusterName}
echo OldClusterName=${OldClusterName}
echo OldInstanceName=${OldInstanceName}
echo DeleteOldCluster=${DeleteOldCluster}

if [[ -z $DomainId ]] || [[ -z $RecordName ]] || [[ -z $NewClusterEndpoint ]] || [[ -z $RecordType ]] || [[ -z $RecordTtl ]] || [[ -z $ApiKey ]] || [[ -z $SecretKey ]]
then
	echo "This script update DNS one record on DME.

 Usage: $0 --domainid ID --recordname NAME --recordtype TYPE --recordttl TTL --apikey APIKEY --secretkey SECRETKEY

 examples:
 $0 --domainid 1234 --recordname www --recordtype A --recordttl 86400 --apikey xxxx --secretkey xxxxx
 "
	exit 1
fi

# create property file with api key
cat << EOFF > dnsmeapi.properties
apiKey=$ApiKey
secretKey=$SecretKey
EOFF

# CHECK if record exists, output name of record
UrlCheck="https://api.dnsmadeeasy.com/V2.0/dns/managed/$DomainId/records"

JqSelectName=".data[]| select((.sourceId == $DomainId) and (.name == \"$RecordName\")).name"
CmdCheckName="perl $DnsMeApiPerl -s $UrlCheck| jq -r '$JqSelectName'"

RecordNameExistent=$(eval "$CmdCheckName")

if [[ "$RecordNameExistent" == "$RecordName" ]]
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record $RecordName exists, get Record ID ....."

  JqSelectGet=".data[]| select((.sourceId == $DomainId) and (.name == \"$RecordName\")).id"
  CmdGet="perl $DnsMeApiPerl -s $UrlCheck| jq -r '$JqSelectGet'"

  if eval "$CmdGet" 2>&1 >/dev/null
  then
    RecordId=$(eval $CmdGet)
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record ID is $RecordId, OK."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: when get Record ID of ${RecordName} on DME, EXIT."
    rm -f dnsmeapi.properties
    exit 1
  fi

  UrlUpdate="https://api.dnsmadeeasy.com/V2.0/dns/managed/$DomainId/records/$RecordId/"

  PutUpdateBody="{\"name\":\"$RecordName\",\"type\":\"$RecordType\",\"value\":\"$NewClusterEndpoint.\",\"id\":\"$RecordId\",\"gtdLocation\":\"DEFAULT\",\"ttl\":$RecordTtl}"
  CmdUpdate="perl $DnsMeApiPerl -s $UrlUpdate -X PUT -H accept:application/json -H content-type:application/json -d '$PutUpdateBody'"

  if eval "$CmdUpdate"
  then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record ${RecordName} Updated."
    rm -f dnsmeapi.properties
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: when update record ${RecordName} on DME, EXIT."
    rm -f dnsmeapi.properties
    exit 1
  fi
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record ${RecordName} NOT exists, EXIT."
  rm -f dnsmeapi.properties
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
