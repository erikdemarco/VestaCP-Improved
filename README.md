# VestaCP-Improved
Lightweight &amp; Secure VestaCP

## What This installer do is:
1. Installs VestaCP with: Apache, MariaDB, Remi repository, iptables + Fail2ban  
-) no dns (use 3rd party dns hosting such as cloudflare to hide your server ip)  
-) no mail (use 3rd party mail hosting, to hide your server ip)  
-) no ftp but we use SFTP so its much more safer  
-) no nginx (i know a lot of people will ask why, for me too much software will increase bug and error level on the server so i tend to use as few software as possible, and I will set cloudflare as my cache server as the 1st layer)  
-) multiple vestacp small bugfix (non-security related)
2. Install monit (to make sure all service auto restart after crash) I dont know why vestacp doesnt include monit as built in package (they even already have the setting for monit here: http://c.vestacp.com/rhel/7/monit/)
3. update php & mariadb to the latest stable version
4. optimize php and disable dangerous functions
5. install ssh key (for additional protection please enable this, and it will only allow ssh login from ssh key, and will disable login using password, to protect you from bruteforce) You know even when you just created an instance on DO/Vultr/OVH, the first time you login into ssh, sometimes it already have '9000+ failed login'. so this is a must.
6. optimize httpd including the server's max process (maxclients) based on server specs (vestacp default setting is out of mind, it is set to 200, for static content its ok but for dynamic content its crazy. lets say each process need 50 mb for wordpress the average need 80mb, so 50mb x 200 = 10G. server with 10G will also crash with this setting because theres not enough memory for other process)
7. Disable admin ssh access to nologin (never host a site as admin, its safer to create a user to host your sites)
8. make admin panel, phpmyadmin, mysql only accessible via localhost (you can still access all of this feature by using ssh tunnel its much more safer this way)
9. automatically make backup and upload it to your dropbox every day (you need dropbox api access, but its free). And the great things about this, this will only store the newest version and delete the old one automatically (both on your server and dropbox), no manual maintenance needed from you.
  
  
## Here's the recommendation for 3rd party services:
(For DNS Hosting)  
Hurricane Electric Hosted DNS  
CloudFlare DNS  
ClouDNS  
NameCheap FreeDNS  
Afraid Free DNS  
NSONE.NET  
  
(For Mail Hosting)  
Zoho Mail  
PawnMail  
Inbox.eu  
Yandex  
Mail.ru  
  
## How to install:
```bash
curl -O https://raw.githubusercontent.com/erikdemarco/VestaCP-Improved/master/vesta_improved.sh && bash vesta_improved.sh
```  
  
 Recommended OS: CentOS7
