Table of Contents
1.1 Options available
1.2 Best Approach, why ?
1.3 Scripts
2.1 Script to extract list of files in HDFS from fsimage
2.2 Script to parse hdfs audit logs
2.3 Script to compute list of cold files
2.4 Points to note
2.5 Where to parse the audits ?

1.1 Options available
● Using hdfs-audit logs:
● Using Ranger-HDFS audits logs:
● Enabling dfs.namenode.accesstime.precision
1. Using hdfs-audit logs:
For each request on files audit logs are created which contains information below:
• User who tried to access.
• Timestamp
• Type of operation
• Source

We can write a script to read these files get a list of files which are read in X
number of days. All other files except the ones in the list can be considered as
Cold Data.

2. Using Ranger-HDFS audits logs:
This approach is similar to point 1, only the difference is these audits are stored in
HDFS.

3. Enabling dfs.namenode.accesstime.precision:
If this parameter is enabled, FSImage of name node will have information related
to the last access time. We can simply extract the Fsimage to get the last access
time for each file in HDFS.

1.2 Best approach, why ?
1. Using hdfs-audit logs:
● The availability of these files on filesystem is confirmed. As per customers
policy hdfs-audit logs should be present on the filesystem for at least 13
months.
● Only Active NameNode is responsible to write this audits. So only one
component is involved which lowers down the possibilities of any errors as
compared to the other two approaches.
● This log is purely for hdfs operations.
2. Using Ranger-HDFS audits logs:
● Availability of these files on HDFS are guaranteed.
● Ranger and HDFS components are involved.
● As compared to other two approach the risk of failure is more.
● This audit is for ranger policy defined for HDFS. There can be some corner
case where audits logs are not printed from the policy which gave the
access for the user.
Refer : how ranger audit works?

3. Enabling dfs.namenode.accesstime.precision:
● This is the easiest way!
● The setting dfs.namenode.accesstime.precision controls how often the
NameNode will update the last accessed time for each file. It is specified in
milliseconds. If this value is too low, then the NameNode is forced to write
an edit log transaction to update the file's last access time for each read
request and its performance will suffer.

1.3 Scripts
● fsparser.sh:
Script to read fsimage to list the total files in HDFS
● auditparser.sh:
Script to read hdfs audit logs to find files read in last two months and emit cold files.

● Cold_data.sh:
Script compares the output of fsparser.sh and auditparser.sh to find out cold files in hdfs.

x
Directory Structure:
|
|___ script-file
|___ out
| |___ old_data
| | |____ Files-from-previous-run
| |
| |___ Intermediate-output-files
|
|____output
|___old_data

| |___ Cod-file-from-previous-run
|
|___final
|____ cold_file.out

2.1 Script to extract list of files in HDFS from fsimage: fsparser.sh
On Secondary / Standby: fsparser.sh
#################################################
# This script will parse the latest fsimage on secondary
/ standby namenode at print the
# list of all the files in HDFS.
# 0. Make sure directory name in which scripts are
deployed are same across edge node and namenodes.
# 1. Modify below points based on customer’s environment:
# fsimage_path
# edge node
# user
# script_owner
#
# 2. Password less ssh must be configured between
edgenode and both namenodes.
#################################################

#!/bin/bash
edgenode=edgenode.openstacklocal

# Hardcoded fsimage path

fsimage_path=/hadoop/hdfs/namesecondary/current/

SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`
MODULE_HOME=`dirname ${SCRIPT_HOME}`
log=$SCRIPT_HOME/log
out=$SCRIPT_HOME/out
output=$SCRIPT_HOME/output
final=$output/final

user=`whoami`
current_dir=`pwd`
current_timestamp=`date +"%Y%m%d%H%M%S"`

# If you want to restrict this script to be executed as
specific user
if [ $user == "hdfs" ];then
script_owner=hdfs
else
echo "User ${user} do not have access to execute the
complete script!!"
exit 1
fi
# If you don’t want to restrict this script to be
executed as specific user remove above if condition.

# Creating a directory structure:

# out directory to store intermediate files generated by
the script.
# final directory will have the final result of
respective script.
# old_data will have the files of previous run.
mkdir -p $log
mkdir -p $out
mkdir -p $output/final
mkdir -p $out/old_data
mkdir -p $output/old_data

# To move existing data in out or output to old_data in
respective directory:
files=`ls -ltr $out | grep -v '^d' | sed '1d' | awk
'{print $9}'`
files_to_process=`echo "$files"`

# for out dir
if [ `ls $out | wc -l` -gt 1 ]; then
while read line;do mv -n -f $out/$line $out/old_data;
done <<< "$files_to_process"
fi

# for output dir
count=`ls $final | wc -l`
if [ $count -gt 0 ]; then
mkdir -p
$output/old_data/lastrun_MovedOn_$current_timestamp;

mv $final/* -n -f
$output/old_data/lastrun_MovedOn_$current_timestamp
fi

# To get the latest fsimage
fsimage=`ls -ltr $fsimage_path | grep fsimage | grep -v
md5 | sort -r | awk '{print $9}' | head -1`

# copy the fsimage in current location <<<< Make sure
the script location has more space than the size of
fsimage as it will create other temp files as well
cp $fsimage_path/$fsimage $out/$fsimage

# To dump fsimage in a file delimited by \t
hdfs oiv -i $out/$fsimage -o
$out/list_hdfs_files_directories.out.$current_timestamp
-p Delimited

#As we are reading data from fsimage :
#1. Consider you created a file today on HDFS and the
same file was not read by any user.
#2. Audit log related to read operation will not be
logged for that file but it will have audit for
creation.
#3. This info will not be available in the fsimage as
check pointing is not triggered.
#4. Consider a corner case where checkpointing was
completed just after creating the file and before
executing the script, in this case

#5. Newly created file will not be in hotfiles and will
be listed in all files in HDFS.

# To create a list files which are created in last 10
days to avoid a corner case :
for (( i=0 ; i<7; i++))
do
fsfile=`date -d "now -$(( i )) days" +"%Y-%m-%d"` ;
awk -F '\t' '{print $10, $1, $3}'
$out/list_hdfs_files_directories.out.$current_timestamp
| grep -v '^d' | awk -F ' ' '{print $2, $3}' | grep -i
"$fsfile" | awk -F ' ' '{print $1}' >>
$out/last_ten_days.out.$current_timestamp
done

# To list all the files in HDFS from fsimage dump
cat
$out/list_hdfs_files_directories.out.$current_timestamp
| awk -F '\t' '{print $10, $1}' | grep -v "^d" | awk
'{print $2}' > $out/list.out.$current_timestamp

# To list all the files which are not present in the list
of files created in last 10 days:
awk 'FNR==NR{a[$0]=1;next}!($0 in a)'
$out/last_ten_days.out.$current_timestamp
$out/list.out.$current_timestamp >
$final/list_hdfs_files.out.$current_timestamp

# Copying the final list of hdfs files which needs to be
compared with hot files on edge node

scp $final/list_hdfs_files.out.$current_timestamp
$user@$edgenode:$SCRIPT_HOME/list_hdfs_files.out

2.2 Script to parse hdfs audit logs: auditparser.sh

#################################################
# This script will parse the hdfs audits for past two
months. Please note this script does not takes day into
consideration.
# 0. Make sure directory name in which scripts are
deployed are same across edge node and namenodes.
# 1. Modify below points based on customer's environment:
# edge node
# user
# script_owner
# 2. Change the audit path in line no 72 and 78
# 3. Password less ssh must be configured between
edgenode and both namenodes.
#################################################

#!/bin/bash

edgenode=edgenode.openstacklocal
node=`hostname -f`

SCRIPT_PATH="${BASH_SOURCE[0]}";

SCRIPT_HOME=`dirname $SCRIPT_PATH`
MODULE_HOME=`dirname ${SCRIPT_HOME}`
log=$SCRIPT_HOME/log
out=$SCRIPT_HOME/out
output=$SCRIPT_HOME/output
final=$output/final

user=`whoami`
current_dir=`pwd`
current_timestamp=`date +"%Y%m%d%H%M%S"`

# If you want to restrict this script to be executed as
specific user
if [ $user == "hdfs" ];then
script_owner=hdfs
else
echo "User ${user} do not have access to execute the
complete script!!"
exit 1
fi
# If you dont want to restrict this script to be executed
as specific user remove above if condition.

# Creating a directory structure:
# out directory to store intermediate files generated by
the script.
# final directory will have the final result of
respective script.

# old_data will have the files of previous run.
mkdir -p $log
mkdir -p $out
mkdir -p $output/final
mkdir -p $out/old_data
mkdir -p $output/old_data

# To move existing data in out or output to old_data in
respective directory:

# for out dir
files=`ls -ltr $out | grep -v '^d' | sed '1d' | awk
'{print $9}'`
files_to_process=`echo "$files"`
if [ `ls $out | wc -l` -gt 1 ]; then
while read line;do mv -n -f $out/$line $out/old_data;
done <<< "$files_to_process"
fi

# for output dir
count=`ls $final | wc -l`
if [ $count -gt 0 ]; then
mkdir -p
$output/old_data/lastrun_MovedOn_$current_timestamp;
mv $final/* -n -f
$output/old_data/lastrun_MovedOn_$current_timestamp
fi

# To calculate the months for which audit files need to
parse:
till_month=`date -d "$(date +%Y-%m-1) -2 month" +%Y-%m`
last_month=`date -d "$(date +%Y-%m-1) -1 month" +%Y-%m`
current_month=`date -d "$(date +%Y-%m-1) 0 month" +%Y-%m`

# To list all the audit files to parse:
# Replace audit path based on the your configuration:
ls -ltr /var/log/hadoop/hdfs/ | grep -e "$current_month"
-e "$last_month" -e "$till_month" | awk '{print $9}' >
$out/list_hdfs-audit_to_parse.$current_timestamp

# add current audit log
echo hdfs-audit.log >>
$out/list_hdfs-audit_to_parse.$current_timestamp

# add /var/log/hadoop/hdfs (replace the path with
customer location)
sed -i -e 's/^/\/var\/log\/hadoop\/hdfs\//'
$out/list_hdfs-audit_to_parse.$current_timestamp

while read line; do
grep -i "cmd=open" $line | awk -F ' ' '$7 ==
"(auth:PROXY)"' | awk -F ' ' '{print $13}' | sort -u -k
1,1 >> $final/hdfs-audit-parsed.$current_timestamp ;
grep -i "cmd=open" $line | awk -F ' ' '$7 ==
"(auth:KERBEROS)"' | awk -F ' ' '{print $10}' | sort -u
-k 1,1 >> $final/hdfs-audit-parsed.$current_timestamp
;
grep -i "cmd=open" $line | awk -F ' ' '$7 ==
"(auth:TOKEN)"' | grep -i "(auth:TOKEN) via" | awk -F '

' '{print $13}' | sort -u -k 1,1 >>
$final/hdfs-audit-parsed.$current_timestamp ;
grep -i "cmd=open" $line | awk -F ' ' '$7 ==
"(auth:TOKEN)"' | grep -i "(auth:TOKEN)" | grep -v
"(auth:TOKEN) via" | awk -F ' ' '{print $10}' | sort -u
-k 1,1 >> $final/hdfs-audit-parsed.$current_timestamp ;
done < $out/list_hdfs-audit_to_parse.$current_timestamp

sed -i 's/src=//'
$final/hdfs-audit-parsed.$current_timestamp
sed -i 's/ugi=//'
$final/hdfs-audit-parsed.$current_timestamp

scp $final/hdfs-audit-parsed.$current_timestamp
$user@$edgenode:$SCRIPT_HOME/hdfs-audit-parsed-$node.out

2.3 Script to compute list of cold files: cold_data.sh

#################################################
# This script will compare the parsed hdfs audit with the
list of hdfs files and will print only those files which
does not match from list of hdfs file.
# 0. Make sure directory name in which scripts are
deployed are same across edge node and namenodes.
# 1. Modify below points based on customer's environment:
# active

# standby
# user
# script_owner
# 2. Password less ssh must be configured between
edgenode and both namenodes.
#################################################
#!/bin/bash

SCRIPT_PATH="${BASH_SOURCE[0]}";
SCRIPT_HOME=`dirname $SCRIPT_PATH`
MODULE_HOME=`dirname ${SCRIPT_HOME}`
log=$MODULE_HOME/log
out=$MODULE_HOME/out
output=$MODULE_HOME/output
final=$output/final

user=`whoami`
current_dir=`pwd`
current_timestamp=`date +"%Y%m%d%H%M%S"`

active=kartiktest1.openstacklocal
standby=kartiktest2.openstacklocal

# If you want to restrict this script to be executed as
specific user
if [ $user == "hdfs" ];then
script_owner=hdfs

else
echo "User ${user} do not have access to execute the
complete script!!"
exit 1
fi
# If you don't want to restrict this script to be
executed as specific user remove above if condition.

# Creating a directory structure:
# out directory to store intermediate files generated by
the script.
# final directory will have the final result of
respective script.
# old_data will have the files of previous run.
mkdir -p $log
mkdir -p $out
mkdir -p $output/final
mkdir -p $out/old_data
mkdir -p $output/old_data

# To move existing data in out or output to old_data in
respective directory:

# for out dir
files=`ls -ltr $out | grep -v '^d' | sed '1d' | awk
'{print $9}'`
files_to_process=`echo "$files"`
if [ `ls $out | wc -l` -gt 1 ]; then

while read line;do mv -n -f $out/$line $out/old_data;
done <<< "$files_to_process"
fi

# for output dir
count=`ls $final | wc -l`
if [ $count -gt 0 ]; then
mkdir -p
$output/old_data/lastrun_MovedOn_$current_timestamp;
mv $final/* -n -f
$output/old_data/lastrun_MovedOn_$current_timestamp
fi
ssh -q $standby "/tmp/Cold/fsimageparser.sh"
ssh -q $active "/tmp/Cold/auditparser.sh"
ssh -q $standby "/tmp/Cold/auditparser.sh"

mv $MODULE_HOME/list_hdfs_files.out
$out/list_hdfs_files.out
mv $MODULE_HOME/hdfs-audit-parsed-$active.out
$out/hdfs-audit-parsed-$active.out
mv $MODULE_HOME/hdfs-audit-parsed-$standby.out
$out/hdfs-audit-parsed-$standby.out

cat $out/hdfs-audit-parsed-$active.out
$out/hdfs-audit-parsed-$standby.out >>
$out/hdfs-audit-parsed-complete.out

awk 'FNR==NR{a[$0]=1;next}!($0 in a)'
$out/hdfs-audit-parsed-complete.out
$out/list_hdfs_files.out >
$final/cold_files.out.$current_timestamp

2.4 Point to note
What is the source file for this script?
● This script reads data from hdfs-audit logs and FSImage. Please note
ranger-hdfs-audit logs are different than hdfs-audit logs.

What is the definition of cold data in this case?
● Cold data are the files in HDFS which are not read for more than the
previous two months.
● For example: If you are running this script on 10

th April, then the script will

consider hdfs-audit logs from month of Feb till date.

How to Configure?
1. Create the same directory structure on ANN and SNN where you want to
keep the script:
# On NN1:
# mkdir /scripts/Cold-Data
On NN2:
# mkdir /scripts/Cold-Data
On EdgeNode:

# mkdir /scripts/Cold-Data
2. Change the permission to hdfs user recursively on both Name nodes and
edgenode:
# chown –R hdfs:hdfs /scripts/Cold-Data
3. Place cold_data.sh on edge node and fsparser.sh on Standby/Secondary
Namenode :
● Auditparser.sh needs to be on both namenodes.
● Execute permission to shell script
● Define Active NN / SNN in both the script
● Configure Password less SSH for HDFS user between NN.
For example:
1.SSH to NN1
2.Switch user to hdfs
# su – hdfs
3. Generate pair of public and private keys:
# ssh-keygen
4. Copy the content of the public key to authorized_keys file
on NN2 and Edge Node
5. Make sure permission of authorized_keys file is 600
6. Repeat the same process for NN2 and edge node
7. Confirm if password less ssh works:
On NN1:
# ssh hdfs@NN2
# ssh hdfs@Edgenode
On NN2
# ssh hdfs@NN1
# ssh hdfs@Edgenode
On Edge Node:
# ssh hdfs@NN1
# ssh hdfs@NN2

What points to consider before running this script?
● Make sure you have more space than the fsimage in the directory where
script is executed.
● Make sure to delete the files related to previous run to avoid running out of
disk space.
● Script should be executed as hdfs user (can be modified based on
environment). Modify below code in the script based on the service
username for HDFS:
# User should be HDFS
if [ $user == "hdfs" ];then <-- Replace the hdfs user
script_owner=hdfs <-- Replace the hdfs user
else
echo "User ${user} do not have access to execute the
complete script!!"
exit 1
fi
● Set the value of fsimage_path variable, value should be the directory name
where fsimage is located.
fsimage_path=/hadoop/hdfs/namenode/current/
● Cold_data.sh script must be executed by changing the directory where the
script is located.
● Make sure edge node is able to reach and connect to Active NameNode
and Standby-NameNode /Secondary-NameNode on port 22

Why are we using FSImage not the “hdfs dfs –ls –R /” command to return a list
of all files in HDFS?
● We can run recursive list on test clusters but not on Production cluster. This

may create lot of RPC call’s and can cause GC pause for Name Node
process.

2.5 Where to parse the audits ?
As of now, these script parsed audit logs on both Name Nodes and fsimage on
standby Name Node.
Section A Options to identify Cold data:
1. Pure shell script: fsimageparser | auditparser | cold_data
2. combination of hive + shell script
Section B Parsing:
Audit logs:
- In both cases you have to parse hdfs audit logs

Fsimage:
- For 1, fsimage needs to be parsed on standby NN
- For 2, just need to dump and upload to hive.
Section C Frequency of running this tool:
1. Run this tool Monthly / weekly / biweekly
2. If you wish to run daily, then at first you need to run for the
$defination_of_cold_data which is one-time activity.
Then run daily.
Section D Where to parse? How much to parse?
Based on environment to environment and the approach answer to this question

will change.
1. If you are running this daily, its fine to parse the audits on NN.
2. If you are running weekly / bi weekly you need to consider the size of audits
logs generated for that week.
Size of audit logs depends on the activity on HDFS which will differ env to env.
3. you run this monthly, size of audit logs based on that you can decide where
you want to parse the audits on NN or Edge nodes.

What options are available for section D 2 and 3:
a. Parse the audits and fsimage on NN.
b. Compress audits, copy it to edge node and parse it. Parse fsimage on standby
NN.
c. Parse audits and fsimage on the edge node by copying from NN.
d. Have an NFS mount for audits logs. Mount in on edge node and parse the
audits on edge node. For fsimage, either parse it on NN or copy it to edge node
and parse it.
Once you know your customer’s requirement and preferred approach you need
to make changes in the script.