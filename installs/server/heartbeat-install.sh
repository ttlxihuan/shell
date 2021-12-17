#!/bin/bash
#
# HeartBeat快速编译安装shell脚本
# 下载地址：http://www.linux-ha.org/wiki/Download
#
# 安装命令
# bash heartbeat-install.sh new
# bash heartbeat-install.sh $verions_num
# 
# 查看最新版命令
# bash heartbeat-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 15.04+
#
# keepalived由C开发的路由软件，用于高可用自动切换备用节点的一种解决方案
#
#
#
#
#
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
# init_install 20.0.0.0 "https://repo.clickhouse.com/tgz/stable/" 'clickhouse-server-\d+(\.\d+){3}' '\d+(\.\d+){3}'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 4 3 4
# ************** 相关配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$CLICKHOUSE_VERSION --user=hbase --group=hbase "
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=' '$ARGV_options
# ************** 编译安装 ******************
# 下载nginx包
download_software http://$NGINX_HOST/download/nginx-$NGINX_VERSION.tar.gz

# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
info_msg "安装相关已知依赖"



# 编译安装
configure_install $CONFIGURE_OPTIONS
# 创建用户组
add_user hbase
# 配置文件处理
info_msg "hbase 配置文件修改"


# 启动服务


info_msg "安装成功：$INSTALL_NAME-$ELASTICSEARCH_VERSION"



