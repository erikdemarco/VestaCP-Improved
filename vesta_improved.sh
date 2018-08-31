#!/bin/sh

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

#install vestacp LAMP + remi (bypass question)
curl -O http://vestacp.com/pub/vst-install.sh
echo "y" | bash vst-install.sh --nginx no --apache yes --phpfpm no --named no --remi yes --vsftpd no --proftpd no --iptables yes --fail2ban yes --quota no --exim no --dovecot no --spamassassin no --clamav no --softaculous no --mysql yes --postgresql no $vAddString


###---------- optimize httpd --------###

max_children=$(($memory / 102400)) #assume each children needs 100mb (worst case)

httpd_optimized_setting="\n
\n#OPTIMIZED APACHE Setting#
\nKeepAlive On
\nKeepAliveTimeout 3
\n
\n<IfModule prefork.c>
\nStartServers 2
\nMinSpareServers 2
\nMaxSpareServers 5
\nMaxClients $max_children
\nServerLimit $max_children
\nMaxRequestsPerChild 100
\n</IfModule>
\n
\n<IfModule worker.c>
\nStartServers 2
\nMaxClients $max_children
\nMinSpareThreads 2
\nMaxSpareThreads $max_children
\nThreadsPerChild 5
\nMaxRequestsPerChild 100
\n</IfModule>
\n#OPTIMIZED APACHE Setting#
\n"

#append to current httpd settings
echo -e $httpd_optimized_setting >> /etc/httpd/conf/httpd.conf

#restart httpd 
service httpd restart

echo "done optimizing httpd"
###---------- optimize httpd --------###


###---------- add swapfile --------###

# recommended swap size see: https://www.cyberciti.biz/tips/linux-swap-space.html

###Swap space == 2 times RAM size (if RAM < 2GB) [<= 2097152]
###Swap space == Equal RAM size (if RAM > 2G < 8GB) [ > 2097152 <= 8388608]
###Swap space == 0.50 times the size of RAM (if RAM > 8GB) [> 8388608]

if [ $memory -le 2097152 ]
then
    swap_size=$(($memory * 2))
elif [ $memory -gt 2097152 -a $memory -le 8388608 ]
then
    swap_size=$(($memory * 1))
else
    swap_size=$(($memory / 2)) #cant be float number, use bc for float number
fi


dd if=/dev/zero of=/fileswap bs=1024 count=$swap_size
chmod 600 /fileswap
mkswap /fileswap
swapon /fileswap
echo '/fileswap none swap sw 0 0' >> /etc/fstab
free -m

echo "done add swap file"
###---------- add swapfile --------###


###---------- install Monit --------###

yum -y install monit
chkconfig monit on

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

echo "done installing monit"
###---------- install Monit --------###



#install php selector
wget https://raw.githubusercontent.com/Skamasle/sk-php-selector/master/sk-php-selector2.sh
bash sk-php-selector2.sh php70 php71 php72



###---------- add SSH KEY --------###
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

fi
echo "done add ssh key"
###---------- add SSH KEY --------###


###---------- Disable php dangerous functions --------###
sed -i -e 's/disable_functions =/disable_functions = exec,system,passthru,shell_exec,proc_open,popen/g' /etc/php.ini
###---------- Disable php dangerous functions --------###


##$PATH Variable is not updated yet with the current session, so we can access '/usr/local/bin/' without need to reboot
export VESTA=/usr/local/vesta/



###---------- Disable shell login for admin --------###
/usr/local/vesta/bin/v-change-user-shell admin nologin
echo "done disabling shell login for admin"
###---------- Disable shell login for admin --------###


###---------- Protect Admin panel --------###
#make vesta admin panel accessible only for localhost (use ssh tunnel to access it from anywhere something like "ssh user@server -L8083:localhost:8083")
if [ $vProtectAdminPanel == "y" ] || [ $vProtectAdminPanel == "Y" ]; then
  
  #admin panel
  sed -i -e '/8083/ s|0.0.0.0/0|127.0.0.1|' /usr/local/vesta/data/firewall/rules.conf && /usr/local/vesta/bin/v-update-firewall && service vesta restart
  ## OR USE THIS, but if the id is changing it wont work ## /usr/local/vesta/bin/v-change-firewall-rule 2 ACCEPT 127.0.0.1 8083 TCP VestaAdmin && service vesta restart
  
  #fail2ban remove watching admin panel its useless because it can only be accessible from localhost
  sed -i -e '/\[vesta-iptables\]/!b;n;cenabled = false' /etc/fail2ban/jail.local  # ';n' change next 1line after match 
  service fail2ban restart 
  
  #mysql
  sed -i -e '/3306/ s|0.0.0.0/0|127.0.0.1|' /usr/local/vesta/data/firewall/rules.conf && /usr/local/vesta/bin/v-update-firewall && service vesta restart

  #phpmyadmin
  sed -i -e 's/Allow from All/Allow from All\n AllowOverride All/g' /etc/httpd/conf.d/phpMyAdmin.conf
  echo '<RequireAll>
    Require local
  </RequireAll>' > /usr/share/phpMyAdmin/.htaccess
  service httpd restart

fi
echo "done making admin panel only accessible from localhost"
###---------- Protect Admin panel --------###


###---------- dropbox backup --------###
if [ $vDropboxUploader == "y" ] || [ $vDropboxUploader == "Y" ]; then
  ##Automate backup to dropbox (START)

  #get the dropbox uploader api
  cd /  #cd to main dir
  mkdir dropbox
  cd dropbox
  curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o dropbox_uploader.sh
  chmod 755 dropbox_uploader.sh
  echo $vDropboxUploaderKey | ./dropbox_uploader.sh

  #download the cron file
  curl -O https://raw.githubusercontent.com/erikdemarco/VestaCP-Improved/master/dropbox_auto_backup_cron.sh

  #move the cron file for accessiblity
  mv dropbox_auto_backup_cron.sh /usr/local/bin/
  
  #weekly cron at saturdy 3am (make backup)
  /usr/local/vesta/bin/v-add-cron-job admin '0' '3' '*' '*' '6'  'sudo /usr/local/vesta/bin/v-backup-users'
  
  #weekly cron at sunday 3am (upload to dropbox)
  /usr/local/vesta/bin/v-add-cron-job admin '0' '3' '*' '*' '0'  'sh /usr/local/bin/dropbox_auto_backup_cron.sh'

  ##Automate backup to dropbox (END)
fi
echo "installing dropbox backup"
###---------- dropbox backup --------###



#done
echo "Done!";
echo " ";
echo "You can access VestaCP here: https://$vIPAddress:8083/";
echo "Username: admin";
echo "Password: $vPassword";
echo " ";
echo " ";
echo "PLEASE REBOOT THE SERVER ONCE YOU HAVE COPIED THE DETAILS ABOVE. REBOOT COMMAND:    shutdown -r now";
