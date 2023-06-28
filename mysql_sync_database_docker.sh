#!/usr/bin/env bash
if ! type mapfile > /dev/null 2>&1 ; then
  echo "This script need bash 4.x exiting"
	exit 2
fi
set -e

PARSED_OPTIONS=$(getopt -n "$0" -o h --long "source:,target:,db:,user:,password:,tables:"  -- "$@")

while true;
do
  case "$1" in
    --source )
	  SOURCE_MYSQL_HOST=$2
      shift 2;;
    --target )
  	  TARGET_MYSQL_HOST=$2
      shift 2;;
    --db )
      DB=$2
      shift 2;;
    --user )
	  DB_USER=$2
	  shift 2;;
	--password )
	  DB_PASS=$2
	  shift 2;;
	--tables )
	  shift
	  TABLES=$@
	  break;;
    -- )
      shift
      break;;
	* ) break ;;
  esac
done

echo "### Inputs ###
SOURCE_MYSQL_HOST = $SOURCE_MYSQL_HOST
TARGET_MYSQL_HOST = $TARGET_MYSQL_HOST
DB = $DB
DB_USER = $DB_USER
DB_PASS = $DB_PASS
TABLES = $TABLES
"

DOCKER_CMD="docker run -it --rm mysql:8.0"
DUMP_OPTS="--ignore-table=mysql.event --hex-blob --add-drop-table --single-transaction --skip-add-locks --no-tablespaces"

# CHECK SOURCE_MYSQL_HOST if database exists
echo "CHECK connection and grants to ${SOURCE_MYSQL_HOST}"
mysql --host=${SOURCE_MYSQL_HOST} --user=${DB_USER} --password=${DB_PASS} -e 'show tables;' ${DB}

# CHECK TARGET_MYSQL_HOST if database exists
echo "CHECK connection and grants to ${TARGET_MYSQL_HOST}"
mysql --host=${TARGET_MYSQL_HOST} --user=${DB_USER} --password=${DB_PASS} -e 'show tables;' ${DB}


echo "Starting migration"
for TABLE in ${TABLES}
do
	echo "Migrating $TABLE"
	${DOCKER_CMD} mysqldump --host=${SOURCE_MYSQL_HOST} --user=${DB_USER} --password=${DB_PASS} ${DUMP_OPTS} ${DB} ${TABLE} | ${DOCKER_CMD} mysql --host=${TARGET_MYSQL_HOST} --user=${DB_USER} --password=${DB_PASS} --init-command="SET SESSION FOREIGN_KEY_CHECKS=0; SET SESSION UNIQUE_CHECKS=0;" $DB

done
echo "done."
