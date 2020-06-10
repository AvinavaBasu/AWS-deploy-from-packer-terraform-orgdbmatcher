#!/usr/bin/env bash

# for userdata log
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Hello from user-data!"
sudo su - ec2-user

HOME=/home/ec2-user
DEPLOYLOCATION=$HOME/efs/disk01/orgdbmatcher

# Adding File processing alerts in NR
sudo bash -c 'cat >> /etc/newrelic-infra/logging.d/logs.yml << EOF
logs:
  - name: "fileprocessing-logs"
    file: /var/log/alarm.log
EOF'

# Mount EFS
cd $HOME
mkdir efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 10.93.189.37:/ efs

# Fetch latest file
BUCKET=s3://mhub2-artifacts/orgdbmatcher/acceptance/release
KEY=`aws s3 ls $BUCKET --recursive | sort | tail -n 1 | awk '{print $4}'`
FILE=$(basename "$KEY")
FILENAME=${FILE%.*}

echo "S3 bucket : $BUCKET"
echo "Latest Deploymentkit Name : $FILE"
echo "FileName : $FILENAME"

# Copy zip from s3
aws s3 cp $BUCKET/$FILE  $DEPLOYLOCATION/
unzip -o -q $DEPLOYLOCATION/$FILE -d $DEPLOYLOCATION/

# Change in properties file
# build-install.properties
cd $DEPLOYLOCATION/$FILENAME/
sed -i 's/"Enter Tomcat home path"/\/opt\/tomcat9\//' build-install.properties
sed -i 's/"Enter the home path of OrgdbMatcher application in file system"/\/home\/ec2-user\/efs\/disk01\/orgdbmatcher\//' build-install.properties

# for the first time
# ElsevierQsbQueue_immediate.xmls
cd $DEPLOYLOCATION/$FILENAME/confOverride/
sed -i 's/${orgdbmatcher.processingDir:}/\/home\/ec2-user\/efs\/disk01\/mhubclone\//g' ElsevierQsbQueue_immediate.xml

# ElsevierQsbQueue_immediate.xmls
cd $DEPLOYLOCATION/$FILENAME/conf/
sed -i 's/${orgdbmatcher.processingDir:}/\/home\/ec2-user\/efs\/disk01\/mhubclone\//g' ElsevierQsbQueue_immediate.xml

# install_files/tomcat/bin/setenv.sh given execute permissions
#sudo su - ec2-user
cd $DEPLOYLOCATION/$FILENAME/install_files/tomcat/bin/
sudo -u ec2-user chmod 744 setenv.sh
if [ $? -eq 0 ]
then
  echo "Success:SETENV"
else
  echo "Failure:SETENV" >&2
fi

sudo chgrp -R ec2-user /home/ec2-user/efs/disk01/orgdbmatcher/
sudo chown -R ec2-user /home/ec2-user/efs/disk01/orgdbmatcher/

cd $DEPLOYLOCATION/$FILENAME/
sudo -u ec2-user ant -f build-install.xml


# For raising alerts
# create the alarm.log in /var/log/
sudo touch /var/log/alarm.log
sudo chgrp -R ec2-user /var/log/alarm.log
sudo chown -R ec2-user /var/log/alarm.log


# create script for Log file not updated
cd $HOME
sudo -u ec2-user touch appfailjob.sh
chmod u+x appfailjob.sh

# Log file not updated for more than 6 hours

sudo tee -a /home/ec2-user/appfailjob.sh > /dev/null <<EOF
latestdate=\$(tail -1 /home/ec2-user/efs/disk01/orgdbmatcher/logs/FileProcessing.log | awk '{print \$1" " \$2}')
indate=\`echo \$latestdate | awk '{print \$1}'\`
date "+%d/%m/%Y" -d \$indate > /dev/null  2>&1
if [ \$? -eq 1 ]
then
echo "Log file is emppty"
else
getdate=\$(date -d "\$latestdate" +%s)
currentdate=\$(date +%s)
echo "Time lapsed since the last file was dropped is \$((currentdate - getdate)) seconds"
let diff=\$((currentdate - getdate))
if [ \$diff -gt 21600 ]
then
echo 'FileProcessing.log file not updated for more than '\$diff' seconds' >> /var/log/alarm.log
fi
fi
EOF


# create script for File started processing but not finished
cd $HOME
sudo -u ec2-user touch processfail.sh
chmod u+x processfail.sh

# File started to process but not ended for 4 hours
sudo tee -a /home/ec2-user/processfail.sh > /dev/null <<EOF
startarr=\$(ps | awk '{ if(\$6 = '/Started/') { print \$9 }}' /home/ec2-user/efs/disk01/orgdbmatcher/logs/FileProcessing.log| head)
finisharr=\$(ps | awk '{ if(\$6 = '/Finished/') { print \$9 }}' /home/ec2-user/efs/disk01/orgdbmatcher/logs/FileProcessing.log| head)
if [ -z "\$startarr" ] && [ -z "\$finisharr" ]
then 
echo "No file logged till now"
else
unfinishedfiles=\`echo \${startarr[@]} \${finisharr[@]} | tr ' ' '\n' | sort | uniq -u\`
if [ -z "\${unfinishedfiles}" ]
then
echo "All files finished processing"
else
files=\$(echo \$unfinishedfiles | tr " " "\n")
for unfinishedfile in \$files
do
filename=\$(basename "\$unfinishedfile")
echo "\$filename is yet to be processed"
unfinishedrow="\$(grep \$unfinishedfile /home/ec2-user/efs/disk01/orgdbmatcher/logs/FileProcessing.log | tail -1)"
lateststartdate=\`echo \$unfinishedrow | awk '{print \$1" "\$2}'\`
finaldate=\$(date -d "\$lateststartdate" +%s)
sysdate=\$(date +%s)
echo "Time lapsed from start till now is \$((sysdate - finaldate)) seconds"
let timetoprocess=\$((sysdate - finaldate))
if [ "\$timetoprocess" -gt 14400 ]
then
echo ''\$filename' started processing but not finished for more than '\$timetoprocess' seconds' >> /var/log/alarm.log
fi
done
fi
fi
EOF


# cronjob
sudo tee -a cat /etc/cron.allow > /dev/null <<EOF 
root
ec2-user
EOF


# putting the cronscripts in crontab -e
cd $HOME
(crontab -l ; echo "*/2 * * * * /home/ec2-user/appfailjob.sh") | sort - | uniq - | crontab -
(crontab -l ; echo "*/2 * * * * /home/ec2-user/processfail.sh") | sort - | uniq - | crontab -
sudo systemctl start crond

# Run Tomcat
cd $HOME
touch tomcat9.service
sudo tee -a tomcat9.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat 9
After=network.target
[Service]
Type=forking
Environment=JAVA_HOME=/usr/lib/jvm/adoptopenjdk-11-hotspot
Environment=CATALINA_HOME=/opt/tomcat9
Environment=CATALINA_BASE=/opt/tomcat9
ExecStart=/opt/tomcat9/bin/startup.sh
ExecStop=/opt/tomcat9/bin/shutdown.sh
User=ec2-user
Group=ec2-user
RestartSec=60
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo mv /home/ec2-user/tomcat9.service /etc/systemd/system/tomcat9.service
sudo chmod 755 /etc/systemd/system/tomcat9.service
sudo systemctl daemon-reload
sudo systemctl enable tomcat9
sudo systemctl start tomcat9


