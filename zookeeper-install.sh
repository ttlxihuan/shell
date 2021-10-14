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
# 获取工作目录
INSTALL_NAME='zookeeper'
# 获取版本配置
VERSION_URL="https://dlcdn.apache.org/zookeeper/"
VERSION_MATCH='zookeeper-\d+\.\d+\.\d+'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本，目前没有找到更低版本的下载位置
ZOOKEEPER_VERSION_MIN='3.5.9'
# 初始化安装
init_install ZOOKEEPER_VERSION
# ************** 编译安装 ******************
chdir $INSTALL_NAME
# 下载kzookeeper包
download_software "https://mirrors.bfsu.edu.cn/apache/zookeeper/zookeeper-$ZOOKEEPER_VERSION/apache-zookeeper-$ZOOKEEPER_VERSION.tar.gz"
# 复制安装包
mkdir -p $INSTALL_PATH/$ZOOKEEPER_VERSION
cp -R ./* $INSTALL_PATH/$ZOOKEEPER_VERSION
cd $INSTALL_PATH/$ZOOKEEPER_VERSION
# 安装java
tools_install java
# 创建用户
add_user zookeeper
# 开放权限，需要开发上级目录，否则启动易容异常
chown -R zookeeper:zookeeper ../
# 复制默认配置文件
if [ ! -e "./conf/zoo.cfg" ];then
    cp ./conf/zoo_sample.cfg ./conf/zoo.cfg
fi

# 启动服务端服务
sudo -u zookeeper ./bin/zkServer.sh start

echo "install zookeeper-$ZOOKEEPER_VERSION success!";
