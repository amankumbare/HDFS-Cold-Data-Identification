#####################################################################
#
# Prerequisites 
# Confirm below variables
# hdfs username
# fsimage_path
# active_nn
# stand_nn
# Password less ssh should be configured for user hdfs
####################################################################


#!/bin/bash

# Navigate to the directory where script is located <<<<<<<<<<<<<<<<<
su - hdfs ;

# Hardcoded fsimage path  				<<<<<<<<<<<<<<<<<<<<<
fsimage_path=/hadoop/hdfs/namesecondary/current/

SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`
MODULE_HOME=`dirname ${SCRIPT_HOME}`
log=$SCRIPT_HOME/log
out=$SCRIPT_HOME/out
output=$SCRIPT_HOME/output
final=$output/final
current_timestamp=`date +"%Y%m%d%H%M%S"`

# Define NN  					<<<<<<<<<<<<<<<<<<<<<<<<<
active_nn=172.26.67.38
stand_nn=172.26.67.39

user=`whoami`
current_dir=`pwd`

SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`

# User should be HDFS <-- Replace the hdfs user			<<<<<<<<<<<<<<<<<<<<<<<<<
if [ $user == "hdfs" ];then
script_owner=hdfs
else
echo "User ${user} do not have access to execute the complete script!!"
exit 1
fi



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

# To get the latest fsimage
fsimage=`ls -ltr $fsimage_path | grep fsimage | grep -v md5 | sort -r | awk '{print $9}' | head -1`


# NEED TO RUN OF STANDBY NN or SECONDARYNN

# copy the fsimage in current location  <<<< Make sure the script location has more space than to the size of fsimage as it will create other temp files as well
cp  $fsimage_path/$fsimage $out/$fsimage

# To get a list of hdfs files and directories from fsimage
hdfs oiv -i $out/$fsimage -o $out/list_hdfs_files_directories.out.$current_timestamp -p Delimited

# Print permissions and files/directories from FSimage
cat $out/list_hdfs_files_directories.out.$current_timestamp | awk -F '\t' '{print $10, $1}' > $out/permission_files_directories.out.$current_timestamp

# To get a list of files only and ignore directory
grep -v "^d" $out/permission_files_directories.out.$current_timestamp | awk '{print $2}' > $final/list_hdfs_files.out.$current_timestamp

scp $final/list_hdfs_files.out.$current_timestamp $user@$active_nn:$SCRIPT_HOME
