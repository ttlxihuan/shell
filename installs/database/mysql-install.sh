#!/bin/bash
#
# mysql快速编译安装shell脚本
#
# 安装命令
# bash mysql-install.sh new [--password=str] [--type=[main|slave]] [--master-host=str] [--master-password=str]
# bash mysql-install.sh $verions_num [--password=str] [--type=[main|slave]] [--master-host=str] [--master-password=str]
# 
# 查看最新版命令
# bash mysql-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 下载地址
#  https://dev.mysql.com/downloads/mysql/
#  system 选择 Source Code 选择对应的源码
# 
#  编译说明文档 https://dev.mysql.com/doc/refman/8.0/en/source-configuration-options.html
#
#  注意mysql字符集校对规则决定了查询时是否区分大小写
#  默认都是不区分大小写
#  *_bin: 表示的是binary case sensitive collation，也就是说是区分大小写的
#  *_cs: case sensitive collation，区分大小写
#  *_ci: case insensitive collation，不区分大小写
#
#  例如：(区分大写小)
#  alter table table_name add field_name varchar(10) character set utf8 collate utf8_bin not null default '' comment '书名';
#
#  创建表时处理默认区分大小写
#  create table table_name(id int primary key auto_increment, name varchar(10) not null)engine=innodb default charset=utf8 collate=utf8_bin comment '表名';
#
#  创建库时处理默认区分大小写
#  create database database_name default charset utf8 collate utf8_bin;
#
# mysql8 开启简单密码
# show VARIABLES like "%password%";
# set global validate_password.check_user_name=0;
# set global validate_password.mixed_case_count=0;
# set global validate_password.number_count=0;
# set global validate_password.policy=0;
# set global validate_password.special_char_count=0;
# set global validate_password.length=1;
#
# mysql5.6 ~ 5.7 开启简单密码
# show VARIABLES like "%password%";
# set global validate_password_policy=0;
# set global validate_password_length=1;
#
# 注意：如果 curl 报 curl: (35) ssl connect error 可以使用 yum install curl 重新安装
#
#
# mysql使用短连接后会给连接端服务器带来很多 TIME_WAIT TCP连接数据，https://cloud.tencent.com/developer/article/1409308
# 一般这种问题不影响什么，但如果太多（比如过万时什么占用大量端口）影响增加连接
# 调整方式有：
# 1、修改 /etc/sysctl.conf 增加如下配置：
# net.ipv4.tcp_tw_reuse = 1
# net.ipv4.tcp_tw_recycle = 1
# net.ipv4.tcp_fin_timeout = 60
#
# 2、加载配置命令：
# sysctl -p
#
# 3、修改mysql的wait_timeout参数，默认这个参数是 86400 可以修改为 60
#    查看命令：show global variables like 'wait_timeout';
#    修改命令：set global wait_timeout=60;
#
# 4、然后慢慢观察会减少TCP TIME_WAIT数量，查看命令：
# netstat -n |grep "^tcp" |awk '{print $6}' |sort|uniq -c |sort -n
#
#
#
#
# 同步报：The replication receiver thread cannot start because the master has GTID_MODE = ON and this server has GTID_MODE = OFF.
# 需要在当前数据库上开启 GTID_MODE
# 1、先关闭同步
#       stop slave;
# 2、开启服务器只允许可以安全使用GTID记录
#       set global enforce_gtid_consistency=on;
# 3、开启GTID_MODE
#       set global gtid_mode=ON;
# 4、如果报错 ERROR 1788 (HY000): The value of @@GLOBAL.GTID_MODE can only be changed one step at a time: OFF <-> OFF_PERMISSIVE <-> ON_PERMISSIVE <-> ON. Also note that this value must be stepped up or down simultaneously on all servers. See the Manual for instructions.
#       set global gtid_mode=OFF_PERMISSIVE;
#       set global gtid_mode=ON_PERMISSIVE;
# 5、稍等片刻再执行
#       set global gtid_mode=ON;
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-p, --password='']安装成功后修改的新密码，默认或为空时随机生成25位密码
[-t, --type='']主从配置 main|slave  ，默认是无主从配置
[-g, --gtid]使用GTID事务唯一标识符进行自动定位复制
# 只有 5.7+ 版本有效
[-H, --master-host='']主从配置地址  user@host 
#配置主服务器时这里指定从服务器连接的账号和地址
#配置从服务器时这里指定主服务器的连接账号和地址
[-P, --master-password='']主从配置密码  password 
#配置主服务器时这里指定从服务器连接的密码
#配置从服务器时这里指定连接主服务器的密码
"
# 定义安装类型
DEFINE_INSTALL_TYPE='cmake'
# 加载基本处理
source $(realpath ${BASH_SOURCE[0]}|sed -r 's/[^\/]+$//')../../includes/install.sh || exit
# 初始化安装
init_install '5.0.0' "https://dev.mysql.com/downloads/mysql/" 'mysql-\d+\.\d+\.\d+'
memory_require 16 # 内存最少G
work_path_require 30 # 安装编译目录最少G
install_path_require 4 # 安装目录最少G
# ************** 参数解析 ******************
# 密码处理
if [ -n "$ARGV_password" ]; then
    MYSQL_ROOT_PASSWORD="$ARGV_password"
else
    # 生成随机密码
    random_password MYSQL_ROOT_PASSWORD 25
fi
# 配置主从
if [ -n "$ARGV_type" ]; then
    if ! [[ $ARGV_type =~ ^(main|slave)$ ]];then
        error_exit "--type 只支持main、slave，现在是：$ARGV_type"
    fi
    MYSQL_SYNC_BIN=$ARGV_type
	MYSQL_SYNC_BIN_PASSWORD=$MYSQL_ROOT_PASSWORD
    # 配置主从
    if [ -n "$ARGV_master_host" ]; then
        MYSQL_SYNC_BIN_HOST=$ARGV_master_host
        if [ -n "$ARGV_master_password" ]; then
            MYSQL_SYNC_BIN_PASSWORD=$ARGV_master_password
        fi
    else
        MYSQL_SYNC_BIN_HOST=$MYSQL_ROOT_PASSWORD
    fi
else
    MYSQL_SYNC_BIN=''
fi
# GTID处理
if [ "$ARGV_gtid" = '1' ] && if_version "$MYSQL_VERSION" "<" "5.7.0"; then
    warn_msg "mysql 必需是 5.7+ 才可以使用GTID复制，--gtid 选项无效。"
fi
# ************** 编译安装 ******************
# 下载mysql包
download_software https://dev.mysql.com/get/Downloads/MySQL-$MYSQL_MAIN_VERSION/mysql-$MYSQL_VERSION.tar.gz
# 暂存编译目录
MYSQL_CONFIGURE_PATH=`pwd`
# mysql-5.7 开始需要使用boots包才能编译
if [ -n "`curl "https://downloads.mysql.com/archives/community/?tpl=version&os=src&version=$MYSQL_VERSION&osva=" 2>&1 | grep "mysql-boost-$MYSQL_VERSION.tar.gz" -o`" ] || [ -n "`curl "https://dev.mysql.com/downloads/mysql/?tpl=platform&os=src&osva="  2>&1 | grep "mysql-boost-$MYSQL_VERSION.tar.gz" -o`" ];then
    download_software https://dev.mysql.com/get/Downloads/MySQL-$MYSQL_MAIN_VERSION/mysql-boost-$MYSQL_VERSION.tar.gz $MYSQL_CONFIGURE_PATH/boost/
    CMAKE_CONFIG="-DWITH_BOOST=../boost/"
    cd $MYSQL_CONFIGURE_PATH
else
    CMAKE_CONFIG='-DDOWNLOAD_BOOST=1 -DWITH_BOOST=../boost/ -DDOWNLOAD_BOOST_TIMEOUT=10000'
fi
# 安装依赖
info_msg "安装相关已知依赖"
# 新版需要cmake3来安装
INSTALL_CMAKE=`cat CMakeLists.txt 2>&1|grep -P 'yum\s+install\s+cmake\d?' -o|grep -P 'cmake\d?' -o`
if [ -z "$INSTALL_CMAKE" ];then
    INSTALL_CMAKE="cmake"
fi
if if_lib "openssl";then
    info_msg 'openssl ok'
else
    # 安装openssl-dev
    packge_manager_run install -OPENSSL_DEVEL_PACKGE_NAMES
fi
if if_lib 'ncurses';then
    info_msg 'ncurses ok'
else
    packge_manager_run install -NCURSES_DEVEL_PACKGE_NAMES
fi
# 新增加的压缩功能，指定使用系统zstd库
# if if_version "$MYSQL_VERSION" ">=" "8.0.18" && [ -d 'extra/zstd' ];then
#     if ! if_command zstd; then
#         download_software https://github.com/facebook/zstd/archive/master.zip zstd-master
#         make_install '' -j 1
#         if_error "make 安装失败"
#         cd $MYSQL_CONFIGURE_PATH
#         CMAKE_CONFIG=$CMAKE_CONFIG" -DWITH_ZSTD=bundled"
#     else
#         CMAKE_CONFIG=$CMAKE_CONFIG" -DWITH_ZSTD=system"
#     fi
# fi
packge_manager_run remove mariadb*
# 获取当前安装要求最低gcc版本
GCC_MIN_VERSION=`grep -P 'GCC \d+(\.\d+)+' cmake/os/Linux.cmake -o|grep -P '\d+(\.\d+)+' -o|tail -n 1`
if [[ "$GCC_MIN_VERSION" =~ ^"\d+\.\d+"$ ]];then
    GCC_MIN_VERSION="$GCC_MIN_VERSION.0"
fi
# 获取当前安装的gcc版本
for ITEM in `which -a gcc`; do
    GCC_CURRENT_VERSION=`$ITEM -v 2>&1|grep -oP '\d+(\.\d+){2}'|tail -n 1`
    if if_version $GCC_MIN_VERSION '<=' $GCC_CURRENT_VERSION;then
        if if_many_version gcc -v;then
            GCC_INSTALL=`echo $ITEM|grep -oP '/([\w+\.]+/)+'`
            CMAKE_CONFIG="-DCMAKE_C_COMPILER="$GCC_INSTALL"gcc -DCMAKE_CXX_COMPILER="$GCC_INSTALL"g++ $CMAKE_CONFIG"
        fi
        break
    fi
done
if ! if_command gcc || if_version $GCC_MIN_VERSION '>' $GCC_CURRENT_VERSION;then
    run_install_shell gcc-install.sh $GCC_MIN_VERSION
    if_error '安装失败：gcc-$GCC_MIN_VERSION'
    CMAKE_CONFIG="-DCMAKE_C_COMPILER=/usr/local/gcc/$GCC_MIN_VERSION/bin/gcc -DCMAKE_CXX_COMPILER=/usr/local/gcc/$GCC_MIN_VERSION/bin/g++ $CMAKE_CONFIG"
fi
# 编译缓存文件删除
if [ -e "CMakeCache.txt" ];then
    rm -f CMakeCache.txt
fi
# 安装编译器
if ! if_command $INSTALL_CMAKE && [[ "$INSTALL_CMAKE" == "cmake3" ]];then
    # get_version CMAKE_MAX_VERSION "https://cmake.org/files/" "v3\.\d+"
    # get_version CMAKE_VERSION "https://cmake.org/files/v$CMAKE_MAX_VERSION" "cmake-\d+\.\d+\.\d+"
    # 3.22.0以上版本文件路径不一样，暂时不安装太高版本
    CMAKE_MAX_VERSION='3.21'
    CMAKE_VERSION='3.21.3'
    download_software "https://cmake.org/files/v$CMAKE_MAX_VERSION/cmake-$CMAKE_VERSION.tar.gz"
    # 编译安装
    configure_install --prefix=$INSTALL_BASE_PATH/cmake3/$CMAKE_VERSION
    ln -svf /$INSTALL_BASE_PATH/cmake3/$CMAKE_VERSION/bin/cmake /usr/bin/$INSTALL_CMAKE
    cd $MYSQL_CONFIGURE_PATH
else
    tools_install $INSTALL_CMAKE
fi
# 编译安装
cmake_install $INSTALL_CMAKE ../ -DCMAKE_INSTALL_PREFIX=$INSTALL_PATH$MYSQL_VERSION -DMYSQL_DATADIR=$INSTALL_PATH$MYSQL_VERSION/database -DSYSCONFDIR=$INSTALL_PATH$MYSQL_VERSION/etc -DSYSTEMD_PID_DIR=$INSTALL_PATH$MYSQL_VERSION/run -DMYSQLX_UNIX_ADDR=$INSTALL_PATH$MYSQL_VERSION/run/mysqlx.sock -DMYSQL_UNIX_ADDR=$INSTALL_PATH$MYSQL_VERSION/run/mysql.sock $CMAKE_CONFIG $ARGV_options

# 创建用户
add_user mysql

cd $INSTALL_PATH$MYSQL_VERSION
MY_CNF="etc/my.cnf"
# 部分目录创建
mkdirs ./run mysql

mkdirs ./database mysql

if [ ! -d "./etc" ];then
    mkdir ./etc
    # 配置文件处理
    if [ ! -e "$MY_CNF" ];then
        if [ -e 'support-files/my-default.cnf' ];then
            cp support-files/my-default.cnf ./etc/my.cnf
        elif [ -e "$SHELL_WROK_TEMP_PATH/mysql/mysql-$MYSQL_VERSION/packaging/rpm-common/my.cnf" ];then
            cp $SHELL_WROK_TEMP_PATH/mysql/mysql-$MYSQL_VERSION/packaging/rpm-common/my.cnf ./etc/my.cnf
        else
            cat > $MY_CNF <<MY_CONF
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/8.0/en/server-configuration-defaults.html

[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove the leading "# " to disable binary logging
# Binary logging captures changes between backups and is enabled by
# default. It's default setting is log_bin=binlog
# disable_log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
#

datadir=database
socket=$INSTALL_PATH$MYSQL_VERSION/run/mysql.sock

log-error=$INSTALL_PATH$MYSQL_VERSION/run/mysqld.log
pid-file=$INSTALL_PATH$MYSQL_VERSION/run/mysqld.pid
MY_CONF
        fi
    fi
fi
touch ./run/mysqld.pid ./run/mysqld.log
chown -R mysql:mysql ./*
info_msg "mysql 配置文件修改"
MYSQL_RUN_PATH="$INSTALL_PATH$MYSQL_VERSION/run"
sed -i "s/^datadir.*=.*data.*/datadir=database/" $MY_CNF
sed -i "s#^socket.*=.*#socket=$MYSQL_RUN_PATH/mysql.sock#" $MY_CNF
sed -i "s#^log-error.*=.*#log-error=$MYSQL_RUN_PATH/mysqld.log#" $MY_CNF
sed -i "s#^pid-file.*=.*#pid-file=$MYSQL_RUN_PATH/mysqld.pid#" $MY_CNF
# 获取系统可用内存空间配置缓冲区
if grep -q '^MemAvailable:' /proc/meminfo;then
    BUFFER_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|MemAvailable):'|awk '{count+=$2} END{printf "%d",count/2}')
else
    BUFFER_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|Buffers|Cached):'|awk '{count+=$2} END{printf "%d",count/2}')
fi
if ((BUFFER_MEMORY <= 0));then
    BUFFER_MEMORY=134217728
fi
# 默认模式配置
cat >> $MY_CNF <<MY_CONF
# 启动用户
user=mysql

# SQL处理模式配置，不同版本有对应默认模式
# MySQL的SQL模式不同版本会有些变化，以下部分弃用模式未列出。
# 默认均为严格模式，在生产环境建议使用严格模式，兼容模式容易造成数据写入丢失或转换。
# 写数据时注意：数据类型、字符集、值合法性、值范围等
#
# MySQL8.0默认：ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION。
# MySQL5.7默认：ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION。
#
# 组合模式值：
#   ANSI
#       相当于： REAL_AS_FLOAT, PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, ONLY_FULL_GROUP_BY（MySQL5.7.5开始增加）
#
#   TRADITIONAL
#       MySQL8.0相当于：STRICT_TRANS_TABLES, STRICT_ALL_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_ENGINE_SUBSTITUTION
#
# 标准模式值：
#   ALLOW_INVALID_DATES
#       不要对日期进行全面检查，仅验证月份和日期是否在范围内（比如月份只有1~12，日期段是每月不尽相同），
#       此模式针对date和datetime类型字段，验证失败会变成：0000-00-00，严格模式产生错误失败写入。
#
#   ANSI_QUOTES
#       将双引号解析为标识符引号，即双引号功能类似反引号。
#
#   ERROR_FOR_DIVISION_BY_ZERO
#       除0报错（一般程序除数为0均异常）。mysql除0操作将等于NULL。此模式已经弃用。
#       如果不指定此选项不会产生警告，指定会产生警告如果还启用严格模式将报错。在SQL中还可以指定IGNORE关键字忽略。
#
#   HIGH_NOT_PRECEDENCE
#       提升not运算优先级，默认not运算优先级不尽相同，指定后not将先于其它运算。
#
#   IGNORE_SPACE
#       允许内置函数名与左括号之间有空格（默认内置函数使用时函数后与左括号不能间隔）。
#       启用后内置函数将被视为保留字。自定义的函数或存储允许有空格且不受此模式影响。
#
#   NO_AUTO_CREATE_USER
#       禁止GRANT创建空密码账号。此模式已经弃用
#
#   NO_AUTO_VALUE_ON_ZERO
#       此模式影响指定auto_increment字段处理。当指定auto_increment字段写入0后，MYSQL通常会在遇到0后生成新序列号，启用后禁止自动生成新序列号。
#
#   NO_BACKSLASH_ESCAPES
#       禁用反斜杠字符作为字符串和标识符中的转义字符，指定后反斜杠将视为普通字符串处理，即没有转义字符。
#
#   NO_DIR_IN_CREATE
#       创建表时，忽略所有INDEX DIRECTORY和DATA DIRECTORY指令。此选项在副本服务器上很有用。
#
#   NO_ENGINE_SUBSTITUTION
#       当使用CREATE TABLE或ALTER TABLE之类的语句时指定禁用或未编译的存储引擎时，自动替换为默认存储引擎。不指定SQL中不可用的存储引擎将报错。
#
#   NO_UNSIGNED_SUBTRACTION
#       无符号字段允许写入有符号数值，当为负数时会转为0并写入。不指定将报错。
#
#   NO_ZERO_DATE
#       允许0000-00-00作为有效日期，从8.0开始弃用
#
#   NO_ZERO_IN_DATE
#       允许日期在年的部分是非零但当月或日部分可为0，比如：2010-00-01或2010-01-00，不会自动转为0000-00-00。从8.0开始弃用
#
#   ONLY_FULL_GROUP_BY
#       禁止
#
#   PAD_CHAR_TO_FULL_LENGTH
#       禁止查询时去掉char类型字段后面空格，char定长字段写入长度未满时后面是会补空格填满。从8.0.13开始弃用
#       默认会自动去掉后面的空格字符，指定此参数后保留后面的空格字符并返回.
#
#   PIPES_AS_CONCAT
#       将||视为字符串连接符（类似使用concat函数）而不是 or 运算符。
#
#   REAL_AS_FLOAT
#       将REAL作为FLOAT别名，不指定则REAL是DOUBLE的别名。
#
#   STRICT_ALL_TABLES
#       为所有存储引擎启用严格的SQL模式。无效的数据值被拒绝执行。
#
#   STRICT_TRANS_TABLES
#       为事务存储引擎启用严格的SQL模式，并在可能的情况下为非事务存储引擎启用
#
#   TIME_TRUNCATE_FRACTIONAL
#       当写入TIME、DATE、TIMESTAMP类型字段时有小数秒且小数位数超过限定位数时使用截断而不是四舍五入。默认不指定时是四舍五入。截断可以理解为字符串截取。从8.0起增加。
#
# 兼容模式
# sql_mode=NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
# 严格模式
sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO

# 配置慢查询
#log-slow-queries=
#long_query_time=1s

#重置密码专用，重置密码后必需注释并重启服务
# 8.0及以上版本修改SQL（先去掉密码然后再重启修改密码）：update mysql.user set authentication_string='' where user='root';
# 8.0以下版本修改SQL：update mysql.user set password=password('root') where user='root';
#skip-grant-tables

# 总最大连接数，过小会报Too many connections
max_connections=16384

# 单个用户最大连接数据，为0不限制，默认为0
#max_user_connections=0

# 配置缓冲区容量，如果独享服务器可配置到物理内存的80%左右，如果是共享可配置在50%~70%左右。
# 建议超过1G以上，默认是128M，需要配置整数，最大值=2**(CPU位数64或32)-1。可动态SQL修改
innodb_buffer_pool_size=${BUFFER_MEMORY}

# 配置线程数，线程数过多会在并发时产生过多的线程切换，导致性能不升反降
# 可动态SQL修改
innodb_thread_concurrency=$((TOTAL_THREAD_NUM * 2))
MY_CONF

# 8.0以上，默认的字符集是utf8mb4，php7.0及以前的连接会报未知字符集错
if if_version "$MYSQL_VERSION" ">=" "8.0.0"; then
cat >> $MY_CNF <<MY_CONF
# 8.0以上，默认的字符集是utf8mb4，php7.0及以前的连接会报未知字符集错
character-set-server = utf8
MY_CONF
fi

# 主从配置
if [ -n "$MYSQL_SYNC_BIN" ]; then
    get_ip
    SERVER_ID=`echo "$SERVER_IP"|sed 's/\.//g'|grep -P '\d{6}$' -o`
    cat >> $MY_CNF <<MY_CONF
# 开启二进制日志
log-bin=mysql-bin-sync

# 配置主从唯一ID
server-id=$SERVER_ID
MY_CONF
    if if_version "$MYSQL_VERSION" ">=" "5.7.0"; then
        USE_GTID_COPY='# '
        if [ "$ARGV_gtid" = '1' ];then
            USE_GTID_COPY=''
        fi
        cat >> $MY_CNF <<MY_CONF
# 5.7+ 可以开启GTID复制，避免使用二进制文件+位置复制
# GTID是事务唯一标识符，每个事务都有唯一的标识，且这个标识符允许 2**63-1 ，差不多有92亿亿次的数量限制。超将无法进行事务处理。
${USE_GTID_COPY}gtid_mode=ON
${USE_GTID_COPY}enforce-gtid-consistency=ON
MY_CONF
    fi
    if [[ "$MYSQL_SYNC_BIN" == 'main' ]]; then
        cat >> $MY_CNF <<MY_CONF
# 日志在每次事务提交时写入并刷新到磁盘
innodb_flush_log_at_trx_commit=1

#事务特性,最好设为1
sync_binlog=1

#作为从服务器时的中继日志
#relay_log=school-relay-bin

#可以被从服务器复制的库。二进制需要同步的数据库名
#binlog-do-db=

#不可以被从服务器复制的库
binlog-ignore-db=mysql

# 多主复制时需要配置自增步进值，防止多主产生同时的自增值
auto_increment_increment=1

# 多主复制时需要配置自增开始值，避开自增值相同
auto_increment_offset=1

# 版本要求mysql5.7+ 设置数据提交延时长度，默认为0无延时，有延时会减少提交次数，减少同步队列数（微秒单位）
#binlog_group_commit_sync_delay=10

MY_CONF
    elif [[ "$MYSQL_SYNC_BIN" == 'slave' ]]; then
        PROCESSOR_NUM=`grep 'processor' /proc/cpuinfo|sort -u|wc -l`
        cat >> $MY_CNF <<MY_CONF
# 并行复制，默认为DATABASE（MYSQL5.6兼容值），版本要求MYSQL5.6+
slave_parallel_type=LOGICAL_CLOCK
# 并行复制线程数
slave_parallel_workers=$PROCESSOR_NUM

master_info_repository=TABLE
relay_log_info_repository=TABLE
relay_log_recovery=ON
MY_CONF
    fi
fi

# 初始化处理
info_msg 'mysql 初始化处理'
if [ -e "./scripts/mysql_install_db" ];then
    ./scripts/mysql_install_db --user=mysql
else
    # mysqld --verbose --help  查看参数说明，需要写到文件中
    #./bin/mysqld --initialize --basedir=/opt/mysql --datadir=/opt/mysql/data --user=mysql 指定目录初始化
    ./bin/mysqld --initialize --user=mysql
    ./bin/mysql_ssl_rsa_setup
fi

# get password
if [ -e "$MYSQL_RUN_PATH/mysqld.log" ]; then
    TEMP_PASSWORD=`grep 'temporary password' $MYSQL_RUN_PATH/mysqld.log|grep -P "[^ ]+$" -o`
elif [ -e "~/.mysql_secret" ]; then
    TEMP_PASSWORD=`grep 'temporary password' /var/log/mysqld.log|grep -P "[^ ]+$" -o`
elif [ -e "~/.mysql_secret" ]; then
    TEMP_PASSWORD=`cat ~/.mysql_secret|grep -P "[^\s]+$"`
fi

#./bin/mysqld_safe --user=mysql &
# 增加开机启动
cp support-files/mysql.server /etc/init.d/mysqld
# 添加到service服务处理中
if if_command chkconfig;then
    chkconfig --add /etc/init.d/mysqld
fi
if [ -e "/usr/bin/systemctl" ]; then
    systemctl daemon-reload
    OPEN_SERVICE="systemctl start mysqld"
else
    OPEN_SERVICE="service mysqld start"
fi

run_msg $OPEN_SERVICE

# 重复多次尝试启动服务
for((LOOP_NUM=1;LOOP_NUM<5;LOOP_NUM++))
do
   info_msg "第${LOOP_NUM}次尝试启动mysql";
   eval "$OPEN_SERVICE"
   if [ -z "`netstat -ntlp|grep mysql`" ]; then
       sleep 5;
   else
       break;
   fi
done

# 修改密码，建立主从复制
if [ -n "`netstat -ntlp|grep mysql`" ]; then
    info_msg '修改初始mysql密码';
    info_msg "初始密码: $TEMP_PASSWORD"
    if [ -n "$TEMP_PASSWORD" ]; then
        run_msg "mysql -uroot --password=\"$TEMP_PASSWORD\" -h127.0.0.1 --connect-expired-password -e \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD'\" 2>&1"
        for((LOOP_NUM=1;LOOP_NUM<10;LOOP_NUM++))
        do
            info_msg "第${LOOP_NUM}次尝试修改密码";
            UPDATE_PASSWORD=`mysql -uroot --password="$TEMP_PASSWORD" -h127.0.0.1 --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD'" 2>&1`
            if [[ "$UPDATE_PASSWORD" =~ "ERROR" ]]; then
                info_msg $UPDATE_PASSWORD
                info_msg "修改mysql初始密码失败"
                sleep 5;
            else
                info_msg "新mysql密码: $MYSQL_ROOT_PASSWORD"
                info_msg "新mysql密码已经写入配置文件中备注"
                echo "#  root 密码: $MYSQL_ROOT_PASSWORD" >> $MY_CNF
                break
            fi
        done
    else
        info_msg "没有指定有效新密码，修改mysql初始密码失败，初始密码已经写入配置文件中备注，生产环境注意删除掉"
        echo "# 初始 root 密码: $TEMP_PASSWORD" >> $MY_CNF
    fi
    # 配置主从
    if [ "$MYSQL_SYNC_BIN" = 'main' ]; then
        info_msg '主从配置，当前服务为：main';
        #
        # 数据库指派权限时，如果库名有下划线需要加反斜杠转义否则指派异常
        # 如 GRANT ALL PRIVILEGES ON `tt\_logs`.* TO `dev`@`localhost`
        # show grants for test;  查看用户权限
        # flush privileges; 刷新下
        #
        MASTER_USER=`echo $MYSQL_SYNC_BIN_HOST|grep -P '^[^@]+' -o`
        MASTER_HOST=`echo $MYSQL_SYNC_BIN_HOST|grep -P '[^@]+$' -o`
        # 权限说明 File, Replication Client, Replication
        # File                    Slave_IO_Running 必需项
        # Replication Client      终端基本查询必需项如 show master status;
        # Replication Slave       Slave_SQL_Running  必需项
        run_msg "mysql -uroot --password=\"$MYSQL_ROOT_PASSWORD\" -h127.0.0.1 -e \"create user '$MASTER_USER'@'$MASTER_HOST' IDENTIFIED BY '$MYSQL_SYNC_BIN_PASSWORD'; grant File, Replication Client, Replication Slave on *.* to '$MASTER_USER'@'$MASTER_HOST'; flush privileges;\""
        mysql -uroot --password="$MYSQL_ROOT_PASSWORD" -h127.0.0.1 -e "create user '$MASTER_USER'@'$MASTER_HOST' IDENTIFIED BY '$MYSQL_SYNC_BIN_PASSWORD'; grant File, Replication Client, Replication Slave on *.* to '$MASTER_USER'@'$MASTER_HOST'; flush privileges;"
    elif [ "$MYSQL_SYNC_BIN" = 'slave' ]; then
        info_msg '主从配置，当前服务为：slave';
        if [ "$ARGV_gtid" = '1' ] && if_version "$MYSQL_VERSION" ">=" "5.7.0"; then
            info_msg '配置GTID事务标识二进制日志自动定位复制'
            run_msg "mysql -uroot --password='$MYSQL_ROOT_PASSWORD' -h127.0.0.1 -e \"change master to master_host='$MASTER_HOST',master_user='$MASTER_USER',master_password='$MYSQL_SYNC_BIN_PASSWORD',MASTER_AUTO_POSITION=1; start slave; show slave status \G\""
            mysql -uroot --password="$MYSQL_ROOT_PASSWORD" -h127.0.0.1 -e "stop slave;change master to master_host='$MASTER_HOST',master_user='$MASTER_USER',master_password='$MYSQL_SYNC_BIN_PASSWORD',MASTER_AUTO_POSITION=1;start slave;show slave status \G "
        else
            info_msg '配置二进制日志指定日志文件和位置复制'
            MASTER_USER=`echo $MYSQL_SYNC_BIN_HOST|grep -P '^[^@]+' -o`
            MASTER_HOST=`echo $MYSQL_SYNC_BIN_HOST|grep -P '[^@]+$' -o`
            # 读取主服务器上的同步起始值
            run_msg "mysql -h$MASTER_HOST -u$MASTER_USER --password=\"$MYSQL_SYNC_BIN_PASSWORD\" -e 'SHOW MASTER STATUS' -X 2>&1"
            SQL_RESULT=`mysql -h$MASTER_HOST -u$MASTER_USER --password="$MYSQL_SYNC_BIN_PASSWORD" -e 'SHOW MASTER STATUS' -X 2>&1`
            MASTER_LOG_FILE=`echo $SQL_RESULT|grep -P 'File[^<]+' -o|grep -P '[^>]+$' -o`
            MASTER_LOG_POS=`echo $SQL_RESULT|grep -P 'Position[^<]+' -o|grep -P '\d+$' -o`
            if [ -n "$MASTER_LOG_FILE" ] && [ -n "$MASTER_LOG_POS" ]; then
                run_msg "mysql -uroot --password='$MYSQL_ROOT_PASSWORD' -h127.0.0.1 -e \"change master to master_host='$MASTER_HOST',master_user='$MASTER_USER',master_password='$MYSQL_SYNC_BIN_PASSWORD',MASTER_LOG_FILE='$MASTER_LOG_FILE',MASTER_LOG_POS=$MASTER_LOG_POS; start slave; show slave status \G\""
                mysql -uroot --password="$MYSQL_ROOT_PASSWORD" -h127.0.0.1 -e "stop slave;change master to master_host='$MASTER_HOST',master_user='$MASTER_USER',master_password='$MYSQL_SYNC_BIN_PASSWORD',MASTER_LOG_FILE='$MASTER_LOG_FILE',MASTER_LOG_POS=$MASTER_LOG_POS;start slave;show slave status \G "
            else
                info_msg $SQL_RESULT;
                info_msg '主从配置失败';
            fi
        fi
    else
        info_msg '没有指定主从配置';
    fi
else
    warn_msg 'mysql服务未能启动，无法进行配置';
fi

info_msg "安装成功：mysql-$MYSQL_VERSION";
