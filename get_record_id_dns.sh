#!/usr/bin/env bash
#set -x
# This script get Record ID of a DNS record
# https://dnsmadeeasy.com/pdf/API-Docv2.pdf

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "domainid:,recordname:,apikey:,secretkey:"  -- "$@")
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
#    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Perl script $DnsMeApiPerl exist and not empty, OK"
  sleep 1
else
#    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Perl script $DnsMeApiPerl not exist or empty, EXIT"
  exit 1
fi

if [[ -z $DomainId ]] || [[ -z $RecordName ]] || [[ -z $ApiKey ]] || [[ -z $SecretKey ]]
then
	echo "This script update DNS one record on DME.

 Usage: $0 --domainid ID --recordname NAME --apikey APIKEY --secretkey SECRETKEY

 examples:
 $0 --domainid 1234 --recordname www --apikey xxxx --secretkey xxxxx
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
JqSelect=".data[]| select((.sourceId == $DomainId) and (.name == \"$RecordName\")).name"

CmdCheck="perl $DnsMeApiPerl -s $UrlCheck| jq -r '$JqSelect'"

RecordNameExistent=$(eval "$CmdCheck")

if [[ "$RecordNameExistent" == "$RecordName" ]]
then
#  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record $RecordName exists, get Record ID ....."

  JqSelectGet=".data[]| select((.sourceId == $DomainId) and (.name == \"$RecordName\")).id"
  CmdGet="perl $DnsMeApiPerl -s $UrlCheck| jq -r '$JqSelectGet'"

  if eval "$CmdGet"
  then

#    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record ID= $CmdGet , OK."
    rm -f dnsmeapi.properties
  else
#    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: when get Record ID of ${RecordName} on DME, EXIT."
    rm -f dnsmeapi.properties
    exit 1
  fi
else
#  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Record ${RecordName} NOT exists, EXIT."
  rm -f dnsmeapi.properties
  exit 1
fi

#echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
