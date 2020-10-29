#!/usr/bin/env bash
#set -x
# This script migrate users from Source to Target without usersexcluded

if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "dbuser:,dbpassword:,dbuserexcluded1:,dbuserexcluded2:,newclusterendpoint:,oldclusterendpoint:"  -- "$@")
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
    --dbuserexcluded1 )
      UserExcluded1=$2
      shift 2;;
    --dbuserexcluded2 )
      UserExcluded2=$2
      shift 2;;
    --newclusterendpoint )
      NewClusterEndpoint=$2
      shift 2;;
    --oldclusterendpoint )
      OldClusterEndpoint=$2
      shift 2;;            
		-- )
      shift
      break;;
		* ) break ;;
  esac
done

if [[ -z $DbUser ]] || [[ -z $DbPassword ]] || [[ -z $UserExcluded1 ]] || [[ -z $UserExcluded2 ]] || [[ -z $NewClusterEndpoint ]] || [[ -z $OldClusterEndpoint ]]
then
	echo "This script migrate users from RDS Aurora Mysql Source Host OldClusterEndpoint to RDS Aurora Mysql Target Host NewClusterEndpoint, except to user rdsadmin and Users to Exclude

 Usage: $0 --dbuser DbUser --dbpassword DbPassword --dbuserexcluded1 userexcluded1 --dbuserexcluded2 userexcluded2 --newclusterendpoint NewClusterEndpoint --oldclusterendpoint OldClusterEndpoint

 examples:
 $0 --dbuser dbuser --dbpassword dbpassword --dbuserexcluded1 user1 --dbuserexcluded2 user2 --newclusterendpoint host1 --oldclusterendpoint host2
 "
	exit 1
fi

DumpOpts="--skip-triggers --skip-disable-keys --no-create-info --skip-add-drop-table --single-transaction --skip-add-locks --hex-blob"

# check mysql connections
if
  mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "SHOW DATABASES  LIKE 'foo'" 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

if
  mysql --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "SHOW DATABASES  LIKE 'foo'" 2>&1 >/dev/null
then
	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Check mysql connection to OldClusterEndpoint $OldClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: FAILED mysql connection to OldClusterEndpoint $OldClusterEndpoint, EXIT."
  exit 1
fi

# drop user on NewClusterEndpoint NOT UsersExcluded and rdsadmin
if
  mysql -B -N --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "SELECT CONCAT('\'', user,'\'@\'', host, '\'') FROM user WHERE user not in ('rdsadmin','${UserExcluded1}','${UserExcluded2}','')" mysql > target_mysql_all_users.txt && \
  while read line; do mysql -B -N --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "DROP USER $line"; done < target_mysql_all_users.txt && \
  mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "FLUSH PRIVILEGES" && \
  rm -f target_mysql_all_users.txt
then
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- Drop user on NewClusterEndpoint $NewClusterEndpoint, OK."
else
  echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Drop user on NewClusterEndpoint $NewClusterEndpoint, EXIT."
  exit 1
fi

# users migrate
echo "$(date +"%Y-%m-%d %H:%M:%S") -- Starting user and db Tables migration ...."
for Table in user db
do
  if
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- Start migration of Table $Table..."
  	mysqldump --host=${OldClusterEndpoint} --user=${DbUser} --password=${DbPassword} ${DumpOpts} mysql --tables ${Table} --where="user not in ('rdsadmin','${UserExcluded1}','${UserExcluded2}','');"| mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} --init-command="SET SESSION FOREIGN_KEY_CHECKS=0; SET SESSION UNIQUE_CHECKS=0;" mysql && \
    mysql --host=${NewClusterEndpoint} --user=${DbUser} --password=${DbPassword} -e "FLUSH PRIVILEGES"
  then
  	echo "$(date +"%Y-%m-%d %H:%M:%S") -- Migration of Table $Table, OK."
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") -- ERROR: Migration of Table $Table, EXIT."
    exit 1
  fi
done

echo "$(date +"%Y-%m-%d %H:%M:%S") -- DONE"
