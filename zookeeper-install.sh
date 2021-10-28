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
# CentOS 5+
# Ubuntu 15+
#
# 官方地址：https://zookeeper.apache.org/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 初始化安装
init_install '3.5.9' "https://dlcdn.apache.org/zookeeper/" 'zookeeper-\d+\.\d+\.\d+'
# ************** 编译安装 ******************
chdir $INSTALL_NAME
# 下载kzookeeper包
if if_version $ZOOKEEPER_VERSION '>=' '3.5.5';then
    DOWNLOAD_FILE_TYPE="-bin"
else
    DOWNLOAD_FILE_TYPE=""
fi
download_software "https://mirrors.bfsu.edu.cn/apache/zookeeper/zookeeper-$ZOOKEEPER_VERSION/apache-zookeeper-$ZOOKEEPER_VERSION$DOWNLOAD_FILE_TYPE.tar.gz" apache-zookeeper-$ZOOKEEPER_VERSION$DOWNLOAD_FILE_TYPE
# 创建用户
add_user zookeeper
# 复制安装包
mkdirs $INSTALL_PATH$ZOOKEEPER_VERSION zookeeper
echo '复制所有文件到：'$INSTALL_PATH$ZOOKEEPER_VERSION
cp -R ./* $INSTALL_PATH$ZOOKEEPER_VERSION
cd $INSTALL_PATH$ZOOKEEPER_VERSION
# 安装java
tools_install java
echo 'zookeeper 配置文件修改'
# 复制默认配置文件
if [ ! -e "./conf/zoo.cfg" ];then
    cp ./conf/zoo_sample.cfg ./conf/zoo.cfg
fi
mkdirs run
# 开放权限，需要开发上级目录，否则启动易容异常
chown -R zookeeper:zookeeper ./
# 修改配置
sed -i -r "s/^(dataDir=).*$/\1$(echo "$INSTALL_PATH$ZOOKEEPER_VERSION/"|sed 's/\//\\\//g')run/" ./conf/zoo.cfg

# 启动服务端服务
echo "sudo -u zookeeper ./bin/zkServer.sh --config ./conf start"
sudo -u zookeeper ./bin/zkServer.sh --config ./conf start

RUN_STATUS_OUT=`find $INSTALL_PATH$ZOOKEEPER_VERSION/logs/ -name 'zookeeper*.out'|tail -n 1`
if [ -e "$RUN_STATUS_OUT" ];then
    cat $RUN_STATUS_OUT
fi

echo "安装成功：zookeeper-$ZOOKEEPER_VERSION";
