#!/bin/bash

. ${APP_ROOT}/toolset/setup/basic_cmd.sh

######################################################################################
# Notes:
#  To start Percona-Server 
#
#####################################################################################

if [ $#  -lt 1 ] ; then
    inst_dir=""
else 
    inst_dir=u${1}
fi

if [ "$(ps -aux | grep "/u01/${inst_dir}/my3306/bin/mysqld_safe" | grep -v "grep")" != "" ]; then
    echo "Percona server is running"
    exit 0
fi

#######################################################################################
check_startup_str() {
    local inst_num=${1}
    expected_str=${2}
    max_retry_num=20
    cur_retry=0
    has_started=0
    while [[ ${cur_retry} -lt ${max_retry_num} ]] ;
    do
        echo "Check whether server-${inst_num} has started yet or not ......"
        if [ $(tool_check_exists "/u01/u${inst_num}/my3306/log/alert.log") == 0 ] ; then 
            CHECK_STR=$($(tool_add_sudo) grep "${expected_str}" /u01/u${inst_num}/my3306/log/alert.log)
            if [ "${CHECK_STR}" ] ; then
                let "has_started=1"
                echo "Percona Server-${inst_num} has started successfully"
                break
            fi
        fi
        let "cur_retry++"
        sleep 5
    done

    if [ ${has_started} -eq 0 ]; then
        echo "Hmm...Please check alert.log manually to see why the server has not started yet"
    fi
}

###########################################################################################
# Begin to start percona server
###########################################################################################

#Run step 1: Add 'mysql' test user account and rights
$(tool_add_sudo) groupadd mysql
$(tool_add_sudo) useradd -g mysql mysql

#########################################################################################
initialize_mysql_inst() {
    local inst_num=${1}  
    config_file=${2}
    
    #Backup existing conf if necessary
    if [ $(tool_check_exists "/etc/my_${inst_num}.conf") == 0 ]; then
        cur_day_str=`date +%Y-%m-%d`
        echo "Backup existing /etc/my_${inst_num}.conf ......"
        if [ $(tool_check_exists "/etc/my_${inst_num}.conf_${cur_day_str}") != 0 ]; then
            $(tool_add_sudo) cp /etc/my_${inst_num}.conf /etc/my_${inst_num}.conf_${cur_day_str}
        fi
    fi

    $(tool_add_sudo) cp -f ${APP_ROOT}/apps/mysql/percona_ali_test/config/${config_file} /etc/my_${inst_num}.conf
    sed -i "s/u01/u01\/u${inst_num}/g" /etc/my_${inst_num}.conf
    new_port=3306
    let "new_port+=${inst_num}"
    sed -i "s/port=3306/port=${new_port}/g" /etc/my_${inst_num}.conf

    $(tool_add_sudo) mkdir -p /u01/u${inst_num}/mysql
    $(tool_add_sudo) cp -fr /u01/my3306/share /u01/u${inst_num}/mysql
    $(tool_add_sudo) mkdir -p /u01/u${inst_num}/my3306/tmp
    $(tool_add_sudo) mkdir -p /u01/u${inst_num}/my3306/log
    $(tool_add_sudo) mkdir -p /u01/u${inst_num}/my3306/run

    cur_user=`whoami`
    $(tool_add_sudo) chown -L -R mysql.${cur_user} /u01/u${inst_num}
    $(tool_add_sudo) chown -L -R mysql.${cur_user} /u01
    
    #Initialize database
    INSTALL_DB_CMD="/u01/my3306/scripts/mysql_install_db --defaults-file=/etc/my_${inst_num}.conf "
    new_start_flag=0
    if [ $(tool_check_exists "/u01/my3306/scripts/mysql_install_db") != 0 ] ; then
        new_start_flag=1
        INSTALL_DB_CMD="/u01/my3306/bin/mysqld  --defaults-file=/etc/my_${inst_num}.conf --initialize"
    fi

    echo "Start to initialize database-${inst_num} ......"
    $(tool_add_sudo) ${INSTALL_DB_CMD}   --basedir=/u01/u${inst_num}/my3306 \
                                     --datadir=/u01/u${inst_num}/my3306/data \
                                     --user=mysql

    #Start mysql server
    echo "Start to run mysql server-${inst_num} ......"
    if [ ${new_start_flag} -eq 1 ] ; then 

    #######################################################################################
    ############ Start Server by using new ways for 5.7+ versions #########################
    $(tool_add_sudo) /u01/my3306/bin/mysqld_safe  --defaults-file=/etc/my_${inst_num}.conf \
                                              --user=mysql \
                                              --skip-grant-tables \
                                              --skip-networking  \
                                              --basedir=/u01/u${inst_num}/my3306 \
                                              --datadir=/u01/u${inst_num}/my3306/data &

    check_startup_str ${inst_num} "Starting mysqld daemon with databases"
    sleep 10
    retry=0
    while [[ ${retry} -lt 10 ]] 
    do
        /u01/my3306/bin/mysql -uroot  --socket=/u01/u${inst_num}/my3306/run/mysql.sock << EOF
UPDATE mysql.user SET authentication_string=PASSWORD('123456') WHERE user='root';
UPDATE mysql.user SET authentication_string=PASSWORD('123456') WHERE user='mysql';
flush privileges;
shutdown;
exit
EOF
        if [ $? -eq 0 ] ; then
            break
        fi
        let "retry++"
        sleep 10
    done

    echo "Restart server-${inst_num}......"
    rm -f /u01/u${inst_num}/my3306/log/alert.log
    #Restart server again 
    #ps -aux | grep "u01/u${inst_num}/my3306" | grep -v grep | grep -v start | awk '{print $2}' | xargs kill -9
    retry=0
    while [[ ${retry} -lt 10 ]] 
    do 
        $(tool_add_sudo) /u01/my3306/bin/mysqld_safe --defaults-file=/etc/my_${inst_num}.conf  \
                            --basedir=/u01/u${inst_num}/my3306 \
                            --user=mysql \
                            --datadir=/u01/u${inst_num}/my3306/data &
        if [ "$(ps -aux | grep "u01/u${inst_num}/my3306" | grep -v mysqld_safe | grep -v grep | grep -v skip-grant-tables)" ] ; then
            break
        fi
        echo "Try to restart server-${inst_num} again ......"
        let "retry++"
        sleep 5
    done

    check_startup_str ${inst_num} "Starting mysqld daemon with databases"
    
else
    #################################################################################### 
    ########### Start server by using old ways for pre 5.7 versions ####################
    $(tool_add_sudo) /u01/my3306/bin/mysqld_safe --defaults-file=/etc/my_${inst_num}.conf  \
                            --basedir=/u01/u${inst_num}/my3306 \
                            --datadir=/u01/u${inst_num}/my3306/data &

    #Check whether server has started successfully or not
    check_startup_str ${inst_num} "ready for connection"

    #Install Step 6:set root rights and create initial database
    /u01/my3306/bin/mysql -uroot << EOF
SET PASSWORD=PASSWORD('123456');
UPDATE mysql.user SET password=PASSWORD('123456') WHERE user='mysql';
GRANT ALL PRIVILEGES ON *.* TO mysql@localhost IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO mysql@"%" IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO root@localhost IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO root@"%" IDENTIFIED BY '123456' WITH GRANT OPTION;
create database sysbench;
EOF

fi
}

#######################################################################################
init_root_rights() {
    /u01/my3306/bin/mysql -uroot --connect-expired-password --socket=/u01/u${1}/my3306/run/mysql.sock -p'123456'<< EOF
ALTER USER USER() IDENTIFIED BY '123456';
GRANT ALL PRIVILEGES ON *.* TO mysql@localhost IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO mysql@"%" IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO root@localhost IDENTIFIED BY '123456' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO root@"%" IDENTIFIED BY '123456' WITH GRANT OPTION;
flush privileges;
create database sysbench;
exit
EOF
}

if [ $# -lt 1 ] ; then
    initialize_mysql_inst "00" "my.conf" 
else 
    cur_inst=${1}
    
    if [ -z "$(ps -aux | grep "/u01/u${cur_inst}"/ | grep -v grep | grep -v mysqld_safe | grep -v skip-grant-tables)" ] ; then
        initialize_mysql_inst ${cur_inst} my_lot_inst.conf
    fi
    
    sleep 10
    init_root_rights ${cur_inst}
fi

echo "========================================================================================="
echo "Percona server-${1} has been started successfully"
