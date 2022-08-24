#!/bin/bash
#
# hbase快速编译安装shell脚本
# 官方地址：https://hbase.apache.org/
# 官方中文文档：http://abloz.com/hbase/book.html
#
# 安装命令
# bash hbase-install.sh new
# bash hbase-install.sh $verions_num
# 
# 查看最新版命令
# bash hbase-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# HBase是java开发的分布式数据库，支持TB级数据量，主要用于Hadoop使用
#
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS="

"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit

# 初始化安装
init_install 1.0.0 "https://hbase.apache.org/downloads.html" 'hbase-\d+(\.\d+){2}-bin.tar.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 编译安装 ******************
# 下载hbase包
download_software https://dlcdn.apache.org/hbase/$HBASE_VERSION/hbase-$HBASE_VERSION-bin.tar.gz

# 暂存编译目录
ELASTICSEARCH_CONFIGURE_PATH=$(pwd)

# 安装依赖
info_msg "安装相关已知依赖"

# 安装验证 java
install_java

cd $ELASTICSEARCH_CONFIGURE_PATH
# 复制安装包并创建用户
copy_install hbase

# 数据目录
# mkdirs data
mkdirs logs hbase
mkdirs tmp hbase

# 配置文件处理
info_msg "hbase 配置文件修改"
# sed  conf/hbase-site.xml
# 添加必需环境变量
sed -i -r 's/^#?\s*(export\s+JAVA_HOME=\s*).*$/\1'$(which java|sed 's,/bin/java,,'|sed 's,/,\\/,')'/' conf/hbase-env.sh
# 指定PID
sed -i -r "s,^#?\s*(export\s+HBASE_PID_DIR\s*=).*$,\1$(echo "$INSTALL_PATH$HBASE_VERSION/tmp"|sed 's/\//\\\//g')," conf/hbase-env.sh
# 增加gc选项
sed -i -r "s,^#?\s*(export\s+HBASE_OPTS\s*).*$,\1=-XX:ParallelGCThreads=$TOTAL_THREAD_NUM," conf/hbase-env.sh

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="./bin/start-hbase.sh"
SERVICES_CONFIG[$SERVICES_CONFIG_STOP_RUN]="./bin/stop-hbase.sh"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="hbase"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_FILE]="./tmp/hbase-hbase-master.pid"
# 服务并启动服务
add_service SERVICES_CONFIG

info_msg "安装成功：$INSTALL_NAME-$HBASE_VERSION"
