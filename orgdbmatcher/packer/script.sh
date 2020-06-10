#!/bin/bash
sudo yum -y update
#additional

sudo yum install -y rpm-build && git clone https://github.com/aws/aws-ec2-instance-connect-config.git && cd aws-ec2-instance-connect-config && make rpm && sudo rpm -i ec2-instance-connect-1.1-12.noarch.rpm && sudo yum remove -y rpm-build
sudo sed -i -e "s/#AuthorizedKeysCommand none/AuthorizedKeysCommand \\/opt\\/aws\\/bin\\/eic_run_authorized_keys %u %f/" /etc/ssh/sshd_config
sudo sed -i -e "s/#AuthorizedKeysCommandUser nobody/AuthorizedKeysCommandUser ec2-user/" /etc/ssh/sshd_config
sudo sed -i -e "s/license_key: ###REPLACE_ME###/license_key: a5d2a889f6a8b00c43cbb4be2c3d80f62424869f/" /etc/newrelic-infra.yml

sudo bash -c 'cat > /etc/newrelic-infra/logging.d/logs.yml << EOF
logs:
  - name: "acceptance-orgdbmatcher-application-logs"
    file: /opt/tomcat9/logs/catalina.out
EOF'

#java installation
cd /tmp
wget https://adoptopenjdk.jfrog.io/adoptopenjdk/rpm/centos/7/x86_64/Packages/adoptopenjdk-11-hotspot-11.0.3+7-1.x86_64.rpm
sudo yum -y localinstall adoptopenjdk-11-hotspot-11.0.3+7-1.x86_64.rpm

#tomact server installation
cd /tmp
wget https://mirrors.sonic.net/apache/tomcat/tomcat-9/v9.0.35/bin/apache-tomcat-9.0.35.tar.gz
tar -xf apache-tomcat-9.0.35.tar.gz
sudo mv apache-tomcat-9.0.35 /opt/tomcat9/
echo "export catalina_home="/opt/tomcat9"">> ~/.bashrc
source ~/.bashrc

#ant installation
cd /tmp
wget https://apache.claz.org//ant/binaries/apache-ant-1.9.15-bin.zip
unzip apache-ant-1.9.15-bin.zip
sudo  mv apache-ant-1.9.15/ /opt/ant
sudo ln -s /opt/ant/bin/ant /usr/bin/ant
cd /etc/profile.d/
sudo tee -a ant.sh > /dev/null <<EOF
ANT_HOME=/opt/ant
PATH=$ANT_HOME/bin:$PATH
export PATH ANT_HOME
export CLASSPATH=.
EOF
sudo chmod +x /etc/profile.d/ant.sh
source /etc/profile.d/ant.sh


