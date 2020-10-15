#!/usr/bin/env bash
#set -x
# This script migrate diff tables of db from Source to Target

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "dbuser:,dbpassword:,db:"  -- "$@")
eval set -- "$PARSED_OPTIONS"

while true;
do
  case "$1" in
    --dbuser )
  	  DbUser=$2
  	  shift 2;;
  	--dbpassword )
  	  DbPassword=$2
  	  shift 2;;
  	--db )
  	  Db=$2
  	  shift 2;;
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
echo OldClusterEndpoint=${OldClusterEndpoint}
echo NewClusterName=${NewClusterName}
echo OldClusterName=${OldClusterName}
echo OldInstanceName=${OldInstanceName}
echo DeleteOldCluster=${DeleteOldCluster}

if [[ -z $DbUser ]] || [[ -z $DbPassword ]] || [[ -z $Db ]] || [[ -z $NewClusterEndpoint ]] || [[ -z $OldClusterEndpoint ]]
then
	echo "This script migrate from RDS Aurora Mysql Source Host to RDS Aurora Mysql Target Host tables in Db that are not in Target.

 Usage: $0 --dbuser DbUser --dbpassword DbPassword --db Db

 examples:
 $0 --dbuser dbuser --dbpassword dbpassword --db
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

# show table in Source and in Target
if
  mysql -B -N --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "SHOW TABLES IN ${Db}" | sort > source_all_tables.txt && \
  mysql -B -N --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "SHOW TABLES IN ${Db}" | sort > target_all_tables.txt && \
  # only tables that are present in Source and are not present in Target
  comm -23 source_all_tables.txt target_all_tables.txt | tr '\r\n' ' ' > diff_tables_in_source.txt && \
  mapfile DiffTables < diff_tables_in_source.txt && \
  rm -f source_all_tables.txt target_all_tables.txt diff_tables_in_source.txt
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Create Diff tables between OldClusterEndpoint $OldClusterEndpoint and NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Create Diff tables between OldClusterEndpoint $OldClusterEndpoint and NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- Starting migration Diff Tables...."
for DiffTables in ${DiffTables}
do
  if
  	mysqldump --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} ${DumpOpts} ${Db} ${DiffTables} | mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} --init-command="SET SESSION FOREIGN_KEY_CHECKS=0; SET SESSION UNIQUE_CHECKS=0;" $Db
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Migration of Diff Table $DiffTables, OK."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Migration of Diff Table $DiffTables, EXIT."
    exit 1
  fi
done

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
