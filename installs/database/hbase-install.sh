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
DEFINE_INSTALL_PARAMS="

"
# 加载基本处理
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../../includes/install.sh || exit

error_exit '此脚本暂未开发完！'

# 初始化安装
init_install 1.0.0 "https://hbase.apache.org/downloads.html" 'hbase-\d+(\.\d+){2}-bin.tar.gz'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 编译安装 ******************
# 下载nginx包
download_software https://www.apache.org/dyn/closer.lua/hbase/$HBASE_VERSION/hbase-$HBASE_VERSION-bin.tar.gz

# 安装依赖
info_msg "安装相关已知依赖"
packge_manager_run install -JAVA_PACKGE_NAMES
if ! if_command java;then
    error_exit '安装java失败'
fi
# 创建用户
add_user hbase
# 复制安装包
mkdirs $INSTALL_PATH$HBASE_VERSION
info_msg '复制所有文件到：'$INSTALL_PATH$HBASE_VERSION
cp -R ./* $INSTALL_PATH$HBASE_VERSION
cd $INSTALL_PATH$HBASE_VERSION
# 数据目录
# mkdirs data
# 修改权限
chown -R hbase:hbase ./*

# 配置文件处理
info_msg "hbase 配置文件修改"
# sed  conf/hbase-site.xml

# 启动服务
sudo -u hbase ./bin/start-hbase.sh

info_msg "安装成功：$INSTALL_NAME-$HBASE_VERSION"
