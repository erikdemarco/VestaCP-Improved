#!/bin/sh

#----------------------------------------------------------#
#                   settings                               #
#----------------------------------------------------------#

#text colors
redtext() { echo "$(tput setaf 1)$*$(tput setaf 9)"; }
greentext() { echo "$(tput setaf 2)$*$(tput setaf 9)"; }
yellowtext() { echo "$(tput setaf 3)$*$(tput setaf 9)"; }

#func to check installed yum package
function yumIsInstalled {
  if yum list installed "$@" >/dev/null 2>&1; then
    true
  else
    false
  fi
}

# Defining return code check function
check_result() {
    if [ $1 -ne 0 ]
    then
	redtext "Error: $2"
        exit $1
    else
    	greentext "Finished: $2"
    fi
}

#php version
phpV='72'

#mariadb version. dont use '10.0' , '10.1', theres a bug causing error
mariadbV='10.2'


#get info
memory=$(grep 'MemTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9])  #get current server ram size
vIPAddress=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
vHostname=$(hostname -f)
read -r -p "What e-mail address would you like to receive VestaCP alerts to? " vEmail
read -r -p "Please type a password to use with VestaCP: " vPassword
read -r -p "Do you want to add SSH Key? [y/N] 
(if you don't have ssh key, you can generate it yourself using using tool like PuTTYgen) " vAddSsh

if [ $vAddSsh == "y" ] || [ $vAddSsh == "Y" ]; then
  read -r -p "Please input your public SSH Key: " vSshKey
fi

read -r -p "Do you want to make admin panel, mysql, and phpmyadmin accesible to localhost only (you can still access admin panel using SSH tunnel)? [y/N] " vProtectAdminPanel

read -r -p "Do you want to automated backup to dropbox weekly? (needs dropbox access token) [y/N] " vDropboxUploader
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  read -r -p "Please input your dropbox Generated access token: " vDropboxUploaderKey
fi


vAddString="--hostname $vHostname --email $vEmail --password $vPassword"


#----------------------------------------------------------#
#                   install vestacp                        #
#----------------------------------------------------------#

#install vestacp LAMP + remi (bypass question)
curl -O http://vestacp.com/pub/vst-install.sh
echo "y" | bash vst-install.sh --nginx no --apache yes --phpfpm no --named no --remi yes --vsftpd no --proftpd no --iptables yes --fail2ban yes --quota no --exim no --dovecot no --spamassassin no --clamav no --softaculous no --mysql yes --postgresql no $vAddString --force

greentext "Vestacp installed"

#install yum-utils (needed for yum-config-manager)
if yumIsInstalled yum-utils
then
	echo "yum-utils already installed"
else
	yum install -y yum-utils
fi


#----------------------------------------------------------#
#                   needed variable                        #
#----------------------------------------------------------#

##$PATH Variable is not updated yet with the current session, so we can access '/usr/local/bin/' without need to reboot
export VERSION='rhel'
export release=$(grep -o "[0-9]" /etc/redhat-release |head -n1)
export VESTA=/usr/local/vesta/
export vestacp="$VESTA/install/$VERSION/$release"
export BIN="$VESTA/bin"



#----------------------------------------------------------#
#                   	  bugfix                           #
#----------------------------------------------------------#

# Random password generator
generate_password() {
    matrix=$1
    lenght=$2
    if [ -z "$matrix" ]; then
        matrix=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
    fi
    if [ -z "$lenght" ]; then
        lenght=10
    fi
    i=1
    while [ $i -le $lenght ]; do
        pass="$pass${matrix:$(($RANDOM%${#matrix})):1}"
       ((i++))
    done
    echo "$pass"
}

# Adding LE autorenew cronjob
if [ -z "$(grep v-update-lets $VESTA/data/users/admin/cron.conf)" ]; then
    min=$(generate_password '012345' '2')
    hour=$(generate_password '1234567' '1')
    cmd="sudo $BIN/v-update-letsencrypt-ssl"
    $BIN/v-add-cron-job admin "$min" "$hour" '*' '*' '*' "$cmd" > /dev/null
fi


#----------------------------------------------------------#
#              fix vestacp default template bug            #
#----------------------------------------------------------#

greentext "fixing template bug..."

#clone template from basedir
cp -f /usr/local/vesta/data/templates/web/httpd/basedir.tpl /usr/local/vesta/data/templates/web/httpd/correct_default.tpl
cp -f /usr/local/vesta/data/templates/web/httpd/basedir.stpl /usr/local/vesta/data/templates/web/httpd/correct_default.stpl

#deactivate 'open_basedir' line from the new template
sed -i -e '/open_basedir/s/.*/#deleted#/' /usr/local/vesta/data/templates/web/httpd/correct_default.stpl
sed -i -e '/open_basedir/s/.*/#deleted#/' /usr/local/vesta/data/templates/web/httpd/correct_default.tpl



#----------------------------------------------------------#
#                   add swapfile                           #
#----------------------------------------------------------#

# just add swap for memory below 1.5gb because swapfile decrease performance even on SSD, because RAM speed is usually 10-20x faster than SSD


if [ $memory -le 999999 ]
then
    #already created from vestacp
    swap_size=0
    yellowtext "skip adding swap file"
elif [ $memory -gt 999999 -a $memory -le 1536000 ] 
then
    swap_size=$(($memory * 2))
    greentext "adding swap file"
else
    swap_size=0
    yellowtext "skip adding swap file"
fi

#only create swap if swap_size not 0
if [ $swap_size -ne 0 ]
then
	dd if=/dev/zero of=/fileswap bs=1024 count=$swap_size
	chmod 600 /fileswap
	mkswap /fileswap
	swapon /fileswap
	echo '/fileswap none swap sw 0 0' >> /etc/fstab
	free -m
fi





#----------------------------------------------------------#
#              update php & mariadb                        #
#----------------------------------------------------------#

##---- update php -----##

greentext "updating php..."

#install ioncube
yum install -y php-ioncube-loader
service httpd restart

#update php
yum-config-manager --enable remi-php${phpV}
yum update -y
check_result $? 'updating php'



##---- update mariadb -----##

greentext "updating mariadb..."

#backup my.cnf before uninstalling mariadb
mv /etc/my.cnf /etc/my.cnf.savebackup

#remove old mariadb
yum remove -y mariadb* MariaDB*

#Add a new MariaDB repository
echo -e "[mariadb]\\nname = MariaDB\\nbaseurl = http://yum.mariadb.org/${mariadbV}/centos7-amd64\\ngpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB\\ngpgcheck=1" > /etc/yum.repos.d/mariadb.repo

#Clean the repository cache
yum clean all

#Install MariaDB
#yum install -y MariaDB-server MariaDB-client
yum install -y mariadb mariadb-server
check_result $? 'updating mariadb'

#rettached old my.cnf
rm -f /etc/my.cnf
mv /etc/my.cnf.savebackup /etc/my.cnf

#enable mariadb to start on boot and start the service
systemctl start mariadb
systemctl enable mariadb

#upgrade database to latest version 
mysql_upgrade

#mysql_secure_installation (do we need this? mysql can only be accessed via localhost)


#----------------------------------------------------------#
#                   optimize httpd                         #
#----------------------------------------------------------#

greentext "optimizing httpd..."

#https://serversforhackers.com/c/php-fpm-process-management
#https://www.kinamo.be/en/support/faq/determining-the-correct-number-of-child-processes-for-php-fpm-on-nginx
#http://dasunhegoda.com/configure-apache-multi-processing-modules-mpms/531/

#calculate how much memory can be use for httpd
swap_size=$(grep 'SwapTotal' /proc/meminfo |tr ' ' '\n' |grep [0-9])  #get swap size
memory_plus_swap=$(($memory + $swap_size))  #physical memory + swap
memory_for_other_process=1024000   #mariadb uses min 1GB
available_memory=$(($memory_plus_swap - $memory_for_other_process))
httpd_memory_percentage=80  #how much memory from available memory to be use for httpd (in percent)
worker_httpd_memory_percentage=95	#should be higher than prefork, because worker tends to use little memory than prefork
httpd_memory=$(($available_memory * $httpd_memory_percentage / 100)) #how many percent of memory should we use for httpd
worker_httpd_memory=$(($available_memory * $worker_httpd_memory_percentage / 100))

max_request_per_child=500
fcgid_maxrequest_per_child=$(($max_request_per_child - 1))	#should be <= PHP_FCGI_MAX_REQUESTS
average_apache_process_size=81920 #assume each children needs 80mb (worst case)
max_children=$(($httpd_memory / $average_apache_process_size))
worker_max_children=$(($worker_httpd_memory / $average_apache_process_size))

#protection max_childern is 0 because too low memory
if [ $max_children -eq 0 ]; then
  max_children=1
fi

prefork_minspareservers=$((30 * $max_children / 100))	#30% from max_children	
prefork_maxspareservers=$(($max_children - $prefork_minspareservers))
prefork_startservers=$prefork_minspareservers #same with min_spare_servers or start as 1 (doesnt really matter)

cpu_core=$(getconf _NPROCESSORS_ONLN)
worker_maxclients=$worker_max_children
worker_serverlimit=$(($cpu_core * 4))
worker_threadsperchild=$(($worker_maxclients / $worker_serverlimit))
worker_minsparethreads=$worker_threadsperchild
worker_maxclients=$(($worker_serverlimit * $worker_threadsperchild))	#readjust worker maxclient (maxclient must be integer multiple of ThreadsPerChild)
worker_maxsparethreads=$(($worker_maxclients - $worker_minsparethreads))

#protection to make sure it not zero and its a number
if [ $cpu_core -ne 0 -a $cpu_core -eq $cpu_core ] 2>/dev/null;
then
    cpu_core=$(getconf _NPROCESSORS_ONLN)
else
    cpu_core=1
fi

httpd_optimized_setting="\n
\n#OPTIMIZED APACHE Setting#
\n
\nServerTokens Prod
\n
\n<IfModule prefork.c>
\nStartServers $prefork_startservers
\nServerLimit $max_children
\nMinSpareServers $prefork_minspareservers
\nMaxSpareServers $prefork_maxspareservers
\nMaxClients $max_children
\nMaxRequestsPerChild $max_request_per_child
\n</IfModule>
\n
\n<IfModule worker.c>
\nServerLimit $worker_serverlimit
\nStartServers 1
\nMinSpareThreads $worker_minsparethreads
\nMaxSpareThreads $worker_maxsparethreads
\nThreadsPerChild $worker_threadsperchild
\nMaxClients $worker_maxclients
\nMaxRequestsPerChild $max_request_per_child
\n</IfModule>
\n
\n<IfModule event.c>
\nServerLimit $worker_serverlimit
\nStartServers 1
\nMinSpareThreads $worker_minsparethreads
\nMaxSpareThreads $worker_maxsparethreads
\nThreadsPerChild $worker_threadsperchild
\nMaxClients $worker_maxclients
\nMaxRequestsPerChild $max_request_per_child
\n</IfModule>
\n
\n<IfModule mod_fcgid.c>
\nFcgidMaxRequestsPerProcess $fcgid_maxrequest_per_child
\nFcgidMaxRequestLen 134217728
\n</IfModule>
\n#OPTIMIZED APACHE Setting#
\n"

#append to current httpd settings
echo -e $httpd_optimized_setting >> /etc/httpd/conf/httpd.conf

#only report if error (default is: warn) but sometimes warn is also important for debugging error
#sed -i -e '/LogLevel/s/.*/LogLevel error/' /etc/httpd/conf/httpd.conf


# -------------------- use 'event' mpm with fcgid (phpfpm is still preferable) -------------------- #

#mod_fcgid should not be used read: https://httpd.apache.org/mod_fcgid/mod/mod_fcgid.html (Special PHP considerations) (BUG #001)

#select php handler value=(default/fcgid)
php_handler="default"

if [ $php_handler == "default" ]; then

	#change default web template to use 'correct_default'
	sed -i -e '/WEB_TEMPLATE/ s|default|correct_default|' $VESTA/data/packages/default.pkg		#sed: find 'WEB_TEMPLATE' then replace 'default' with 'correct_default'

	#if modphp selected, do nothing because its the default for this installer
	greentext "default php handler selected"

fi


if [ $php_handler == "fcgid" ]; then

	#https://wiki.apache.org/httpd/php
	
	#change from 'prefork' to 'event' (apache 2.4.6 still has a bug causing content length mismatch so when checked with pingdom there's many connection error, this includes worker and event mpm)
	#sed -i -e '/mod_mpm_prefork.so/s/^/#/' /etc/httpd/conf.modules.d/00-mpm.conf	#sed: add hashtag (#) in front of a line after a 'keyword' match
	#sed -i -e '/mod_mpm_event.so/s/^# *//' /etc/httpd/conf.modules.d/00-mpm.conf	#sed: remove hashtag (#) in front of a line after a 'keyword' match

	#change default web template to use 'phpfcgid' so it uses mod_fcgid instead of mod_php (if vestacp updated with phpfpm thats better, before that happens fcgid with event mpm is preferable now)
	sed -i -e '/WEB_TEMPLATE/ s|default|phpfcgid|' $VESTA/data/packages/default.pkg		#sed: find 'WEB_TEMPLATE' then replace 'default' with 'phpfcgid'

	#fix to prevent bug #001:
	#1.FcgidMaxRequestsPerProcess should be <= PHP_FCGI_MAX_REQUESTS (x - 1 is safer): https://serverfault.com/questions/219922/fastcgi-and-apache-500-error-intermittently
	#2.PHP_FCGI_CHILDREN=0
	#3.PHP_FCGI_MAX_REQUESTS high enough but dont be too high to prevent too much memory leak, dont set to 0 to prevent memory leak
	#4. unrelated but recommended: increase FcgidMaxRequestLen maybe same like uploadpostsize in php
	#change the maxclients for phpfcgid template (sed: find 'match' change all line in that match with 'xxx')
	sed -i -e '/PHP_FCGI_MAX_REQUESTS/s/.*/export PHP_FCGI_MAX_REQUESTS='$maxrequest_per_child'/' $VESTA/data/templates/web/httpd/phpfcgid.sh
	sed -i -e '/PHP_FCGI_CHILDREN/s/.*/export PHP_FCGI_CHILDREN=0/' $VESTA/data/templates/web/httpd/phpfcgid.sh
	
	greentext "fcgid selected as php handler"

fi


# ------------------------------------------------------------------------------------------------ #

#restart httpd 
service httpd restart
check_result $? 'restarting httpd'



#----------------------------------------------------------#
#                   install Monit                          #
#----------------------------------------------------------#

greentext "installing monit"

yum -y install monit
#chkconfig monit on

# Vesta Control Panel
wget http://c.vestacp.com/rhel/7/monit/vesta-nginx.conf -O /etc/monit.d/vesta-nginx.conf
wget http://c.vestacp.com/rhel/7/monit/vesta-php.conf -O /etc/monit.d/vesta-php.conf

# Nginx
# wget http://c.vestacp.com/rhel/7/monit/nginx.conf -O /etc/monit.d/nginx.conf

# vesta-nginx (nginx for admin panel)
wget http://c.vestacp.com/rhel/7/monit/vesta-nginx.conf -O /etc/monit.d/vesta-nginx.conf

# Apache
wget http://c.vestacp.com/rhel/7/monit/httpd.conf -O /etc/monit.d/httpd.conf

# MySQL
wget http://c.vestacp.com/rhel/7/monit/mysql.conf -O /etc/monit.d/mysql.conf

# Exim
# wget http://c.vestacp.com/rhel/7/monit/exim.conf -O /etc/monit.d/exim.conf

# Dovecot
# wget http://c.vestacp.com/rhel/7/monit/dovecot.conf -O /etc/monit.d/dovecot.conf

# ClamAV
# wget http://c.vestacp.com/rhel/7/monit/clamd.conf -O /etc/monit.d/clamd.conf

# Spamassassin
# wget http://c.vestacp.com/rhel/7/monit/spamassassin.conf -O /etc/monit.d/spamassassin.conf

# OpenSSH
wget http://c.vestacp.com/rhel/7/monit/sshd.conf -O /etc/monit.d/sshd.conf

# vesta-php
wget http://c.vestacp.com/rhel/7/monit/vesta-php.conf -O /etc/monit.d/vesta-php.conf

service monit start
check_result $? 'starting monit'



#----------------------------------------------------------#
#                  install php selector                    #
#----------------------------------------------------------#

#disabled because of many bugs
#wget https://raw.githubusercontent.com/Skamasle/sk-php-selector/master/sk-php-selector2.sh
#bash sk-php-selector2.sh php70 php71 php72


#----------------------------------------------------------#
#                  add SSH KEY                             #
#----------------------------------------------------------#

greentext "adding ssh key"

if [ $vAddSsh == "y" ] || [ $vAddSsh == "Y" ]; then

#create the ~/.ssh directory if it does not already exist (it safe beacuse of -p)
mkdir -p ~/.ssh

#add your public key (vps_4096 file)
echo $vSshKey >> ~/.ssh/authorized_keys

#make sure permission and ownership correct
chmod -R go= ~/.ssh
chown -R $USER:$USER ~/.ssh

#disable login with password
sed -i -e 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

#restart ssh
systemctl reload sshd.service
check_result $? 'reloading sshd'

fi



#----------------------------------------------------------#
#               	optimizing php                     #
#----------------------------------------------------------#

greentext "optimizing php..."

#Disable php dangerous functions
sed -i -e 's/disable_functions =/disable_functions = exec,passthru,shell_exec,system/g' /etc/php.ini

#increase upload_max_filesize
sed -i -e '/upload_max_filesize/s/.*/upload_max_filesize = 8M/' /etc/php.ini

#----------------------------------------------------------#
#               Disable shell login for admin              #
#----------------------------------------------------------#

greentext "disabling shell login for admin..."
/usr/local/vesta/bin/v-change-user-shell admin nologin



#----------------------------------------------------------#
#                 Protect Admin panel                      #
#----------------------------------------------------------#

greentext "making admin panel, mysql, phpmyadmin only accessible from localhost..."

#make vesta admin panel accessible only for localhost (use ssh tunnel to access it from anywhere something like "ssh user@server -L8083:localhost:8083")
if [ $vProtectAdminPanel == "y" ] || [ $vProtectAdminPanel == "Y" ]; then
  
  #admin panel
  sed -i -e '/8083/ s|0.0.0.0/0|127.0.0.1|' /usr/local/vesta/data/firewall/rules.conf
  ## OR USE THIS, but if the id is changing it wont work ## /usr/local/vesta/bin/v-change-firewall-rule 2 ACCEPT 127.0.0.1 8083 TCP VestaAdmin && service vesta restart

  #mysql
  sed -i -e '/3306/ s|0.0.0.0/0|127.0.0.1|' /usr/local/vesta/data/firewall/rules.conf

  #update firewall then restart vesta
  /usr/local/vesta/bin/v-update-firewall
  service vesta restart

  #fail2ban remove watching admin panel its useless because it can only be accessible from localhost
  sed -i -e '/\[vesta-iptables\]/!b;n;cenabled = false' /etc/fail2ban/jail.local  # ';n' change next 1line after match 
  service fail2ban restart 

  #phpmyadmin
  sed -i -e 's/Allow from All/Allow from All\n AllowOverride All/g' /etc/httpd/conf.d/phpMyAdmin.conf
  echo '<RequireAll>
    Require local
  </RequireAll>' > /usr/share/phpMyAdmin/.htaccess
  service httpd restart

fi



#----------------------------------------------------------#
#                      dropbox backup                      #
#----------------------------------------------------------#

greentext "installing dropbox backup..."

if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  ##Automate backup to dropbox (START)

  #get the dropbox uploader api
  cd /  #cd to main dir
  mkdir dropbox
  cd dropbox
  curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o dropbox_uploader.sh
  chmod 755 dropbox_uploader.sh
  echo "$vDropboxUploaderKey
  y" | ./dropbox_uploader.sh

  #download the cron file
  curl -O https://gist.githubusercontent.com/erikdemarco/959e3afc29122634631e59d3e3640333/raw/f58557e0ab474eedd480e145e499de584eed6293/dropbox_auto_backup_cron.sh

  #move the cron file for accessiblity & chmod it
  mv dropbox_auto_backup_cron.sh /usr/local/vesta/bin/
  chmod 755 /usr/local/vesta/bin/dropbox_auto_backup_cron.sh 
  
  #daily cron (make backup) at 05.10
  #/usr/local/vesta/bin/v-add-cron-job admin '10' '05' '*' '*' '*'  'sudo /usr/local/vesta/bin/v-backup-users'	#there's already this cron on vestacp default installation
  
  #daily cron (upload to dropbox) at 06.10
  /usr/local/vesta/bin/v-add-cron-job admin '10' '06' '*' '*' '*'  'sudo /usr/local/vesta/bin/dropbox_auto_backup_cron.sh'

  ##Automate backup to dropbox (END)
fi



#----------------------------------------------------------#
#                          Done                            #
#----------------------------------------------------------#

#done
echo "Done!";
echo " ";
echo "You can access VestaCP here: https://$vIPAddress:8083/";
echo "Username: admin";
echo "Password: $vPassword";
echo " ";
echo " ";
echo "PLEASE REBOOT THE SERVER ONCE YOU HAVE COPIED THE DETAILS ABOVE.";

#reboot
read -r -p "Do you want to reboot now? [y/N] " vReboot
if [ $vReboot == "y" ] || [ $vReboot == "Y" ]; then
  reboot
fi
