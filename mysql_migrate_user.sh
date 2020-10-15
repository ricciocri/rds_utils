#!/usr/bin/env bash
#set -x
# This script migrate users from Source to Target without usersexcluded

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "dbuser:,dbpassword:,dbuserexcluded:"  -- "$@")
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
    --dbuserexcluded )
      UserExcluded=$2
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

if [[ -z $DbUser ]] || [[ -z $DbPassword ]] || [[ -z $UserExcluded ]] || [[ -z $NewClusterEndpoint ]] || [[ -z $OldClusterEndpoint ]]
then
	echo "This script migrate users from RDS Aurora Mysql Source Host OldClusterEndpoint to RDS Aurora Mysql Target Host NewClusterEndpoint, except to user rdsadmin and UserExcluded

 Usage: $0 --dbuser DbUser --password DbPassword --dbuserexcluded UserExcluded

 examples:
 $0 --dbuser dbuser --password dbpassword --dbuserexcluded dbuserexcluded
 "
	exit 1
fi

# check mysql connection
if
  mysql --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "SHOW DATABASES  LIKE 'foo'" 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

if
  mysql --host=${OldClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "SHOW DATABASES  LIKE 'foo'" 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to OldClusterEndpoint $OldClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to OldClusterEndpoint $OldClusterEndpoint, EXIT."
  exit 1
fi

# drop user on NewClusterEndpoint NOT UsersExcluded and rdsadmin
if
  mysql -B -N --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "SELECT CONCAT('\'', user,'\'@\'', host, '\'') FROM user WHERE user != 'rdsadmin' AND user != '${UserExcluded}' AND user != ''" mysql > target_mysql_all_users.txt && \
  while read line; do mysql -B -N --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "DROP USER $line"; done < target_mysql_all_users.txt && \
  mysql --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "FLUSH PRIVILEGES" && \
  rm -f target_mysql_all_users.txt
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Drop user on NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Drop user on NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

# export user from OldClusterEndpoint
if
  mysql -B -N --host=${OldClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "SELECT CONCAT('\'', user,'\'@\'', host, '\'') FROM user WHERE user != 'rdsadmin' AND user != '${UserExcluded}' AND user != ''" mysql > source_mysql_all_users.txt && \
  while read line; do mysql -B -N --host=${OldClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "SHOW GRANTS FOR $line"; done < source_mysql_all_users.txt > source_mysql_all_users.sql && \
  sed -i 's/$/;/' source_mysql_all_users.sql
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Export user from OldClusterEndpoint $OldClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Drop user on OldClusterEndpoint $OldClusterEndpoint, EXIT."
  exit 1
fi

# import user to NewClusterEndpoint
if
  mysql --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} < source_mysql_all_users.sql && \
  mysql --host=${NewClusterEndpoint} --dbuser=${DbUser} --password=${DbPassword} -e "FLUSH PRIVILEGES" && \
  rm -f source_mysql_all_users.txt source_mysql_all_users.sql
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Import user to NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Import user to NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
