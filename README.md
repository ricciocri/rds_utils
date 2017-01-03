# rds_utils

These are some shell scripts that I use to manage my RDS Instances on Amazon

# Requisites
  - [JQ](https://stedolan.github.io/jq/) package installed
  - Bash 4.x
  - [aws cli](https://aws.amazon.com/cli/) installed.
  - The system account where you use these shell script must be authenticated with your aws account and be able to operate on your RDS infrastructure (i.e the aws account should have all privileges on the RDS)

## Main goals of these scripts

I use these script on Jenkins to be able to add or removes easily read-replicas on different clusters, this is mainly done by the script scalereplica.sh.


Tested on Debian 8 with Aurora on Amazon RDS.
