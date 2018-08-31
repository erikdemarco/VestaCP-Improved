# VestaCP-Improved
Lightweight &amp; Secure VestaCP

## What This installer do is:
1. Installs VestaCP with: Apache, MariaDB, Remi repository, iptables + Fail2ban
no dns (use 3rd party dns hosting such as cloudflare to hide your server ip), no mail (use 3rd party mail hosting, to hide your server ip), , no ftp but we use SFTP so its much more safer, no nginx (i know a lot of people will ask why, for me too much software will increase bug and error level on the server so i tend to use as few software as possible, and I will set cloudflare as my cache server as the 1st layer)
2. Install monit (to make sure all service auto restart after crash) I dont know why vestacp doesnt include monit as built in package (they even already have the setting for monit here: http://c.vestacp.com/rhel/7/monit/)
3. install php selector
4. add swapfile (virtual memory) and it will automagically calculate the best swapfile size based on server's specs. (also make sure it reattached even after server reboot)
5. install ssh key (for additional protection please enable this, and it will only allow ssh login from ssh key, and will disable login using password, to protect you from bruteforce) You know even when you just created an instance on DO/Vultr/OVH, the first time you login into ssh, sometime it already have 'xxx failed login' GEEZ. so this is a must.
6. optimize server's max process (maxclients) based on server specs (vestacp default setting is out of mind, it is set to 200, for static content its ok but for dynamic content its crazy. lets say each process need 50 mb for wordpress the average need 80mb, so 50mb x 200 = 10G. server with 10G will also crash with this setting because theres not enough memory for other process)
7. Disable only the most dangerous php functions like exec,system,passthru,shell_exec,proc_open,popen
8. Disable admin shell (never host a site as admin, its safer to create a user to host your sites)
9. make admin panel, phpmyadmin, mysql only accessible via localhost (you can still access all of this feature by using ssh tunnel its much more safer this way)
10. automatically make backup and upload it to your dropbox every week (you need dropbox api access, but its free)




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
