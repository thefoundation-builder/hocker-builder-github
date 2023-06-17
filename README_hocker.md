Happy Docker images
===

Suggested:
* frontend proxy: https://gitlab.com/the-foundation/flying-docker-compose-letsencrypt-nginx-proxy-companion

Use cases:

* generic fpm :          https://gitlab.com/the-foundation/docker-generic-php-fpm
* typo3       :          https://gitlab.com/the-foundation/Docker-typo3 along with https://gitlab.com/the-foundation/docker-typo3-src
* websockets along with: https://gitlab.com/the-foundation/docker-addon-domain


### Images , Build status  and Registries
#### Build status

[![Build](https://github.com/thefoundation-builder/hocker-builder-github/actions/workflows/build.yml/badge.svg)](https://github.com/thefoundation-builder/hocker-builder-github/actions/workflows/build.yml)

#### Registries
| Registry | note |  state |
|--|--|--|
| [Quay.io Images](quay.io/repository/thefoundation/hocker) | | |
| [Docker Hub Images](https://hub.docker.com/r/thefoundation/hocker/tags) |  might be deleted/dis-and-re-appear in 2023 ( or not ) |  |

## PHP-FPM Flavour:

## General
* does not log everything , e.g. healthchecks, UptimeRobot etc.
* tries to detect the real IP
* is able to detect php artisan schedule:run    and adds a cronjob automatically
* is able to detect php artisan queue:work       and start 2 supervisor processes that restart every 2h(gracefully)
* is able to detect php artisan websockets:run  and starts 1 websocket process that you have to target with a second container
*


## Features
* provides hardened dropbear with www-data exported via SSH_PORT, shell can be enabled with ENABLE_WWW_SHELL=true
* redis/memcached default ran by supervisord
* restricted basedir (/var/www /tmp) for www-data user
* filters some default status monitors and favicon from log ( `-e 'StatusCabot'-e '"cabot/' -e '"HEAD / HTTP/1.1" 200 - "-" "curl/' -e UptimeRobot/ -e "docker-health-check/over9000" -e "/favicon.ico"` )
* runs apache,mysql(mariadb),dropbear,cron,memcached,redis etc. via **supervisor**
* creates /etc/msmtprc from env and fixes /etc/msmtp.aliases as well
* inserts FROM address with localhost as domain when cronjobs run
* installs php mail extension during startup
* detects php:artisan queue and websockets under `/var/www/` and `/var/www/*/` , inserts them into **supervisor**
* curl healthcheck saves cookies so joomla ( and other's ) session table does not get bloated up  → healthcheck cookies are saved under /dev/shm/.healthcheck-cookies-curl
## disabled functions for php-fpm by default:
```
system,exec,passthru,system,proc_open,popen,parse_ini_file,show_source,chroot,escapeshellcmd,escapeshellarg,shell_exec,proc_open,proc_get_status,ini_restore,ftp_connect,ftp_exec,ftp_get,ftp_login,ftp_nb_fput,ftp_put,ftp_raw
```


## user notes

* -> log in via ssh -p SSH_PORT www-data@yourdomain.tld ( or use sftp, e.g. filezilla )
* -> put your project under /var/www
* -> the webroot is /var/www/html , you may softlink 
   e.g `mv /var/www/html /var/www/html.old ;ln -s /var/www/php-core/public /var/www/html`

## Deletion (GDPR ..)
  
*  remember that logs might persist in docker daemon unless you REMOVE the containers ( stopping is not enough )
*  since the volumes in most/all upstream projects using this containers have bind mound, **the recommendation is to delete from inside the containers** unless you know what you do ( setups might have shared folders etc. )

### Deletion/Pruning (inside )

#### simple setup ( no queues etc. )
* as `www-data` ( e.g. after `wwwsh` )
   ``` 
   mysql -e "drop database $MYSQL_DATABASE_NAME" 
   mysql -e "drop database $MARIADB_DATABASE"
   cd /var/
   (find /var/www -delete 2>&1 |grep -v rmission )
   ```
  ( the `cd` step is nessecary since you might be in /var/www/ == home directory of www-data user)
  
  (very old containers or manually created databases might refuse to drop a database ,
  in that case you might try the following 

  ) 
#### advanced Setup 
* as root in the container
   ```
   supervisorctl stop $(supervisorctl status|cut -d" " -f1)
   find /var/lib/mysql /var/www -delete 
   ```
* `docker stop containername ; docker rm containername ` OR  `docker-compose down` the container

### Deletion/Pruning ( outside )
* `docker stop containername ; docker rm containername ` OR  `docker-compose down` the container first , since queues/mysql might still overwrite and recreate
* find the volumes with e.g. docker-compose or docker inspect ( or docker volumes )
* delete the folders/volumes ( if they are remote you have to mount them first , obviously )


## Commands
| cmd | hint |
|---|---|
| `/usr/bin/enable_accesslog `    | enable /var/log/web.TYPEOFLOG.YYYY-MM-DD.log for one hour  |
| `/usr/bin/restart_websockets `  | kill the php artisan websockets:run process   |
| `wwwsh `  | drop to a www-data `/bin/bash` shell  |


## configuration

### .env Variables

| hint | ENV | default | alt. Name | tested options |
|---|---|---|---|---|
| base domain    | `APP_URL`                | | | `realdomain.tld` |
| notify_address | `MAIL_ADMINISTRATOR`     | | | `adminuser@notifydomain.tld` |
| smtp_host | `MAIL_HOST`              | | | |
| send_from | `MAIL_FROM`              | | | |
| smtp_user | `MAIL_USERNAME`          | | | InternalNoTLSNoAuth , `user@domain.tld` |
| smtp_pass | `MAIL_PASSWORD`          | | |
| php_maxup | `MAX_UPLOAD_MB`          | `128` | | 128 , 256 , 512 , 2048 |
| php_maxinputvars | `PHP_MAX_INPUT_VARS`     | | |8192 |
| php_errlevel | `PHP_ERROR_LEVEL`           | `default`        |  | `(empty)` , `default` , `verbose` |
| php inline | `PHP_SHORT_OPEN_TAG`           | `false`        |  | `(empty)` , `false` , `true` |
| php timeout | `PHP_EXECUTION_TIME`     | `300` | | 30 ,60 , 600 ( cgi socket timeout@601s ) |
| php sessionstore    | `PHP_SESSION_STORAGE`    | `memcached` | | (empty) , `memcached` , `files` , `redis` |
| php session redis   | `PHP_SESSION_REDIS_HOST` | `tcp://127.0.0.1:6379` |  |
| php sess cache time | `PHP_SESSION_CACHETIME_MINUTES`  | `240` |   |   |
| php sess valid time | `PHP_SESSION_VALIDTIME_SECONDS`  | `68400`  |   |   |
| php forbidden funct | `PHP_FORBIDDEN_FUNCTIONS`           | `Europe/Berlin`        |  | `(empty)` , `NONE`, |
| phpfpm allow types  | `PHP_FPM_ALLOWED_EXTENSIONS`  |   |   |  `.php .php3 .php4 .php5 .php7 .html .htm` |
| remote mysql 3306   | `MARIADB_REMOTE_ACCESS`  | `false` | | `(empty)` , `true` , `false` |
| timezone            | `APP_TIMEZONE`           | `Europe/Berlin`        | |




### APACHE:

*  mount a volume that contains `/etc/apache-extra-config-var-www/*.conf` that will bee applied in `<Directory> /var/www`

* letsencrypt cert dir for a domain goes to /etc/ssl/private_letsencrypt

  **Attention**: the files need to be directly in the folder e.g. /etc/ssl/private_letsencrypt/fullchain.pem

* a file in `/etc/rc.local` will run IN PARALLEL to startup with /bin/bash
* a file in `/etc/rc.local.foreground` will run IN FOREGROUND before startup with /bin/bash
  `NOTE:` it will  


### locales
```
  bs_BA.UTF-8
  ca_ES.UTF-8
  cs_CZ.UTF-8
  da_DK.UTF-8
  de_AT.UTF-8
  de_DE.UTF-8
  en_US.UTF-8
  es_ES.UTF-8
  es_MX.UTF-8
  et_EE.UTF-8
  fi_FI.UTF-8
  fr_FR.UTF-8
  it_IT.UTF-8
  ja_JP.UTF-8
  nl_BE.UTF-8
  nl_NL.UTF-8
  pl_PL.UTF-8
  pt_BR.UTF-8
  pt_PT.UTF-8
  ro_RO.UTF-8
  th_TH.UTF-8
  uk_UA.UTF-8
  vi_VN.UTF-8
  zh_CN.UTF-8
  zh_HK.UTF-8
  zh_TW.UTF-8
```
## Screenshots

![alt text](screenshots/ci-test.png "Image tester Screenshot")

---

![alt text](screenshots/ci-gh.png "Image tester Screenshot") 

## in-depth notes:
* php fpm socket under `/run/php/php-fpm.sock` is soft linked like this:

  `ln -s /run/php/php${PHPVersion}-fpm.sock /run/php/php-fpm.sock`



##### A Project of the foundation

<div><img src="https://hcxi2.2ix.ch/github.com/TheFoundation/Hocker/README.md/logo.jpg" width="480" height="270"/></div>
