# rds_utils

These are some shell scripts that I use to manage my RDS Instances on Amazon

# Requisites
  - [JQ](https://stedolan.github.io/jq/) package installed
  - Bash 4.x
  - [aws cli](https://aws.amazon.com/cli/) installed.
  - The system account where you use these shell script must be authenticated with your aws account and be able to operate on your RDS infrastructure (i.e the aws account should have all privileges on the RDS)

## Main goals of these scripts

I use these script on Jenkins to be able to add or removes easily read-replicas on different clusters, this is mainly done by the script **scalereplica.sh**, I use it to clone automatically all the tags from the writer and with my sns ARN to automatically create an alarm on CPU usage.

Examples
```bash
scalereplica.sh myaurora-cluster 3 # <-- This bring the total number of readers to 3 on the cluster myaurora-cluster
scalereplica.sh myaurora-cluster 0 # <-- This delete all the instances of type reader
scalereplica.sh myaurora-cluster 3 arn:aws:sns:eu-west-1:8281216198:mycontact # <-- This bring the total number of readers to 3 and for each set a Cloudwatch alarm on CPU usage.
```

Also I use the **elastic-rds.sh** script on cron (every 5 minutes) to monitor the average CPU of the read replicas and add or remove instances looking at the average cpu in use.

Tested on Debian 8 with Aurora on Amazon RDS.
