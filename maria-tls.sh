#!/bin/bash

country="US"
state="CA"
locality="SJ"
org="tcooktst"
cn="neohousedesign.com"
cert_days="36500"

line_space() {
  line1="$1"

  linecount=$(echo $line1 | awk '{print length}')
  add3="3"
  total_lines=`echo $(expr "$linecount" + $add3)`
  printf '=%.0s' $(eval "echo {1.."$(($total_lines))"}");
  printf "\n %-20s %40s\n"  "$line1"  "$line2"
  printf '=%.0s' $(eval "echo {1.."$(($total_lines))"}");
  printf '\n'
  printf "\n"
}

error_check() {
 if [ $? -ne "0" ]; then
   line_space "$1"
   exit
 fi
}

build_ssl() {
 cd /etc/pki/tls/certs/
 mkdir mariadb
 cd mariadb
 openssl genrsa 2048 > ca-key.pem
 openssl req -new -x509 -nodes -days $cert_days -key ca-key.pem -out ca.pem -subj "/C=$country/ST=$state/L=$locality/O=$org/CN=$cn"
 openssl req -newkey rsa:2048 -days $cert_days -nodes -subj "/C=$country/ST=$state/L=$locality/O=$org/CN=$cn" -keyout server-key.pem -out server-req.pem
 openssl rsa -in server-key.pem -out server-key.pem
 openssl x509 -req -in server-req.pem -days $cert_days -CA ca.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
 chmod mysql. *
}

#this function is only used for initial db setup and configuration.
install_db() {
  yum install mariadb-server
  error_check "Mariadb was not installed successfully, please check your logs in /var/log/messages!"

  systemctl enable mariadb
  error_check "Mariadb was intalled successfully, but unable to enable in systemctl!"

  systemctl start  mariadb
  error_check "Unable to start Mariadb successfully, check /var/log/messages for hints as to why!"

  mysql -e   'UPDATE user SET password=PASSWORD("P1ckl3") WHERE user="root" AND Host = "localhost";' mysql
  error_check "Unable to create root user in Mariadb or set password, try the following command manually by logging into mysql and using the mysql database: UPDATE user SET password=PASSWORD(\"P1ckl3\") WH
ERE user=\"root\" AND Host = \"localhost\";"

  mysql -e "FLUSH PRIVILEGES;"
  error_check "mysql privileges were not flushed successfully, try running the following from within mysql: FLUSH PRIVILEGES;"

  mysql -u root -pP1ckl3 -e 'GRANT ALL PRIVILEGES ON * . * TO "morpheusadmin"@"%" IDENTIFIED BY "P1ckl!" with grant option;' mysql
  error_check "Unable to create morpheusadmin user: see instructions, or try to run the following manually from mysql: GRANT ALL PRIVILEGES ON * . * TO \"morpheusadmin\"@\"%\" IDENTIFIED BY \"P1ckl!\" wi
th grant option;"

  mysql -u root -pP1ckl3 -e 'SHOW GRANTS FOR "morpheusadmin"@"%";' mysql
  error_check "Grants display for morpheusadmin user failed:"

}

#non invasive checks and backup of original my.cnf
maria_flt_chk() {
 cd /etc/
 error_check "Changing to directory /etc/ failed!"

 find . -name 'my.cnf' | egrep '.*'  1>/dev/null
 error_check "Unable to find file my.cnf, double check you have mariadb-server installed. $ rpm -qa | grep maria."

 find .  -name 'my.cnf.orig'  | egrep '.*' 1>/dev/null
 if [ $? -eq "0" ]; then
  line_space "Backup of my.cnf, my.cnf.orig already exists: exiting! Please remove current /etc/my.cnf.orig file and re run $0."
   exit
 fi

 cp my.cnf my.cnf.orig
 error_check "Unsuccessful at creating a backup of original my.cnf file in /etc/"

}

#function for presenting db to choose.
options() {
  option1=("db1" "db2")
  select option in "${option1[@]}"
    do
      dbs=$option
      break
    done
}

#execute selection function, declaring which db the my.cnf file will be created for.
options

db_select() {
if [ "$dbs" == "db1" ];
 then
  db="2"
  serverid="1"
else
  db="1"
  serverid="2"
fi
}

#Define ip to assign to db.
ip=$(hostname -I | awk '{print $1}')

#Write my.cnf to /etc/my.cnf
my_cnf_wr() {
cat << EOF >/etc/my.cnf
 [mysqld]
 datadir=/var/lib/mysql
 socket=/var/lib/mysql/mysql.sock
 # Disabling symbolic-links is recommended to prevent assorted security risks
 symbolic-links=0
 # Settings user and group are ignored when systemd is used.
 # If you need to run mysqld under a different user or group,
 # customize your systemd unit file for mariadb according to the
 # instructions in http://fedoraproject.org/wiki/Systemd

 server_id=$serverid
 replicate-do-db=morpheusdb
 log_bin="/var/log/mariadb/binary-log"
 relay_log="/var/log/mariadb/relay-log"
 expire_logs_days=7
 log_slave_updates=1
 bind_address=$ip
 auto_increment_increment=2
 auto_increment_offset=$db
 binlog_format=MIXED


 [mysqld_safe]

 ssl
 ssl-ca=/etc/pki/tls/certs/mariadb/server-req.pem
 ssl-cert=/etc/pki/tls/certs/mariadb/server-cert.pem
 ssl-key=/etc/pki/tls/certs/mariadb/server-key.pem

 log_error=/var/log/mariadb/mariadb.log
 pid_file=/var/run/mariadb/mariadb.pid

 #
 # include all files from the config directory
 #
 !includedir /etc/my.cnf.d
EOF
}

sysctl_ssl() {
 sed -i   s/basedir/"ssl --basedir"/g /lib/systemd/system/mariadb.service
 error_check "unable to add ssl to sysctl maria startup:"

 systemctl daemon-reload
 error_check "systemctl daemon did not reload properly:"
}

maria_flt_chk

my_cnf_wr

#systemctl restart mariadb
#error_check "Unable to restart Mariadb server: run systemctl status mariadb:"

build_ssl
sysctl_ssl
