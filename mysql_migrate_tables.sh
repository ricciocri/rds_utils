#!/usr/bin/env bash
#set -x
# This script migrate tables from Source to Target

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi
set -e

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "db:,dbuser:,dbpassword:,tables:"  -- "$@")

while true;
do
  case "$1" in
    --db )
      Db=$2
      shift 2;;
    --dbuser )
  	  DbUser=$2
  	  shift 2;;
  	--dbpassword )
  	  DbPassword=$2
  	  shift 2;;
  	--tables )
  	  shift
  	  Tables=$@
  	  break;;
    -- )
      shift
      break;;
	* ) break ;;
  esac
done

VarsSourceFile="./vars-clonedbcluster"

if [[ -f "$VarsSourceFile" && -s "$VarsSourceFile" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile exist and not empty, OK"
else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Var file $VarsSourceFile not exist or empty, EXIT"
    exit 1
fi

. ./vars-clonedbcluster

echo NewClusterEndpoint=${NewClusterEndpoint}
echo NewClusterReaderEndpoint=${NewClusterReaderEndpoint}
echo OldClusterEndpoint=${OldClusterEndpoint}
echo NewClusterName=${NewClusterName}
echo OldClusterName=${OldClusterName}
echo OldInstanceWriterName=${OldInstanceWriterName}
echo OldInstanceReaderName=${OldInstanceReaderName}
echo DeleteOldCluster=${DeleteOldCluster}
echo AddReadReplica=${AddReadReplica}

if [[ -z $DbUser ]] || [[ -z $DbPassword ]] || [[ -z $Db ]] || [[ -z $Tables ]] || [[ -z $NewClusterEndpoint ]] || [[ -z $OldClusterEndpoint ]]
then
	echo "This script migrate tables in Database Db from RDS Aurora Mysql Source Host to RDS Aurora Mysql Target Host

 Usage: $0 --dbuser DbUser --dbpassword DbPassword --db Db --tables tables_list

 examples:
 $0 --dbuser dbuser --dbpassword dbpassword --db database --tables a b c d
 "
	exit 1
fi

DumpOpts="--ignore-table=mysql.event --hex-blob --add-drop-table --single-transaction --skip-add-locks"

# check mysql connection
if
  mysql --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e 'show tables;' ${Db} 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to OldClusterEndpoint $OldClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to OldClusterEndpoint $OldClusterEndpoint, EXIT."
  exit 1
fi

if
  mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e 'show tables;' ${Db} 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- Starting Tables migration ...."
for Table in ${Tables}
do
  if
  	mysqldump --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} ${DumpOpts} ${Db} ${Table} | mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} --init-command="SET SESSION FOREIGN_KEY_CHECKS=0; SET SESSION UNIQUE_CHECKS=0;" $Db
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Migration of Table $Table, OK."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Migration of Table $Table, EXIT."
    exit 1
  fi
done

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
