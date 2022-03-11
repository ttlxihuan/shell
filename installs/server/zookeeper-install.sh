#!/bin/bash
#
# zookeeper快速编译安装shell脚本
#
# 安装命令
# bash zookeeper-install.sh new
# bash zookeeper-install.sh $verions_num
# 
# 查看最新版命令
# bash zookeeper-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# 官方地址：https://zookeeper.apache.org/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '3.5.9' "https://dlcdn.apache.org/zookeeper/" 'zookeeper-\d+\.\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 4
# ************** 编译安装 ******************
# 下载kzookeeper包
if if_version $ZOOKEEPER_VERSION '>=' '3.5.5';then
    DOWNLOAD_FILE_TYPE="-bin"
else
    DOWNLOAD_FILE_TYPE=""
fi
download_software "https://mirrors.bfsu.edu.cn/apache/zookeeper/zookeeper-$ZOOKEEPER_VERSION/apache-zookeeper-$ZOOKEEPER_VERSION$DOWNLOAD_FILE_TYPE.tar.gz" apache-zookeeper-$ZOOKEEPER_VERSION$DOWNLOAD_FILE_TYPE
# 安装java
packge_manager_run install -JAVA_PACKGE_NAMES
if ! if_command java;then
    error_exit '安装java失败'
fi

# 复制安装包并创建用户
copy_install zookeeper

info_msg 'zookeeper 配置文件修改'
# 复制默认配置文件
if [ ! -e "./conf/zoo.cfg" ];then
    sudo_msg zookeeper cp ./conf/zoo_sample.cfg ./conf/zoo.cfg
fi
mkdirs run zookeeper

# 修改配置
sed -i -r "s/^(dataDir=).*$/\1$(echo "$INSTALL_PATH$ZOOKEEPER_VERSION/"|sed 's/\//\\\//g')run/" ./conf/zoo.cfg

# 启动服务端服务
sudo_msg zookeeper ./bin/zkServer.sh --config ./conf start

RUN_STATUS_OUT=`find $INSTALL_PATH$ZOOKEEPER_VERSION/logs/ -name 'zookeeper*.out'|tail -n 1`
if [ -e "$RUN_STATUS_OUT" ];then
    cat $RUN_STATUS_OUT
fi

info_msg "安装成功：zookeeper-$ZOOKEEPER_VERSION";
