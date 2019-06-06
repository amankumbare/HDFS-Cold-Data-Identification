#####################################################################
# This script is created to find cold data, Data which is not read for 2 months 
# Author: Premier Support Team Cloudera #
# Version: v0.1 #
# Last Updated: 12/04/2019 
#
# Prerequisites 
# Confirm below variables
# hdfs username
# active_nn
# stand_nn
# Password less ssh should be configured for user hdfs
# Replace hdfs username in ssh command
####################################################################


#!/bin/bash

# Name Node Details <<<<<<<<<<<<<
active_nn=172.26.67.38
stand_nn=172.26.67.39



SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`
MODULE_HOME=`dirname ${SCRIPT_HOME}`
log=$MODULE_HOME/log
out=$MODULE_HOME/out
output=$MODULE_HOME/output


user=`whoami`
current_dir=`pwd`
current_timestamp=`date +"%Y%m%d%H%M%S"`
previous_run=`date -d "$(date +%Y-%m-1) -2 month" +%Y-%m`
SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`
final=$output/final

# To get the months required
#fsimage_path=/hadoop/hdfs/namenode/current/

# To get the latest fsimage
#fsimage=`ls -ltr $fsimage_path | grep fsimage | grep -v md5 | sort -r | awk '{print $9}' | head -1`


till_month=`date -d "$(date +%Y-%m-1) -2 month" +%Y-%m`
last_month=`date -d "$(date +%Y-%m-1) -1 month" +%Y-%m` 
current_month=`date -d "$(date +%Y-%m-1) 0 month" +%Y-%m`





# User should be HDFS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<
if [ $user == "hdfs" ];then
script_owner=hdfs
else
echo "User ${user} do not have access to execute the complete script!!"
exit 1
fi


# Replace path to scritp on SNN <<<<<<<<<<<<<<<<<<
ssh $user@$stand_nn /tmp/akshay/fsparser.sh

mkdir -p $log

# intermediate data
mkdir -p $out

# Final Result where cold files will be present
mkdir -p $output/final

# To move old files if any 
mkdir -p $out/old_data   
mkdir -p $output/old_data


# To move existing data in out or output to old_data in respective directory
files=`ls -ltr $out | grep -v '^d' | sed '1d' | awk '{print $9}'`
files_to_process=`echo "$files"`

if [ `ls $out | wc -l` -gt 1 ]; then
while read line;do mv -n -f $out/$line $out/old_data; done <<< "$files_to_process"
fi

count=`ls $final | wc -l`
if [ $count -gt 0 ]; then
mkdir -p $output/old_data/lastrun_MovedOn_$current_timestamp;
mv $final/* -n -f $output/old_data/lastrun_MovedOn_$current_timestamp
fi


# list audit files for current, last, and till month write. Print only the hdfs-audits to parse
ls -ltr /var/log/hadoop/hdfs/ | grep -e "$current_month" -e "$last_month" -e "$till_month" | awk '{print $9}' > $out/list_hdfs-audit_to_parse.$current_timestamp


# add current audit log
echo hdfs-audit.log  >> $out/list_hdfs-audit_to_parse.$current_timestamp


# add /var/log/hadoop/hdfs (replace the path with customer location)	
sed -i -e 's/^/\/var\/log\/hadoop\/hdfs\//' $out/list_hdfs-audit_to_parse.$current_timestamp



# For each file audit file to parse, grep for cmd=open and print required columns only.
while read line; do grep -i "cmd=open" $line | awk -F ' ' '{print $1, $2, $6, $9, $10}' >> $out/tempfin.out.$current_timestamp ;done < $out/list_hdfs-audit_to_parse.$current_timestamp


#remove src keyword and print only the hot files 
sed 's/src=//' $out/tempfin.out.$current_timestamp | awk '{print $5}' | sort | uniq  > $out/hot_files.out.$current_timestamp


list_files=`ls -ltr $MODULE_HOME | grep -v '^d' | grep list_hdfs_files.out | sort -r | head -1 | awk '{print $9}'`

mv $MODULE_HOME/$list_files $out/$list_files

# To print only those files from list of files available in HDFS which are not present in hot_files.txt
awk 'FNR==NR{a[$0]=1;next}!($0 in a)' $out/hot_files.out.$current_timestamp $out/$list_files > $final/cold_files.out.$current_timestamp

