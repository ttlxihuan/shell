#!/bin/bash
#
# kubernetes快速编译安装shell脚本
#
# 安装命令
# bash kubernetes-install.sh new
# bash kubernetes-install.sh $verions_num
# 
# 查看最新版命令
# bash kubernetes-install.sh
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 官方地址：https://kubernetes.io/zh/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='kubernetes'
# 获取版本配置
VERSION_URL="https://kubernetes.io/releases/"
VERSION_MATCH='>\d+\.\d+\.\d+'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
KUBERNETES_VERSION_MIN='1.19.1'
# 初始化安装
init_install KUBERNETES_VERSION
# ************** 编译安装 ******************
chdir $INSTALL_NAME
# 下载kubernetes包

curl -LO "https://dl.k8s.io/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl"
if_error 'download fail: kubectl'
curl -LO "https://dl.k8s.io/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl.sha256"
if_error 'download fail: kubectl.sha256'
echo "$(<kubectl.sha256) kubectl" | sha256sum --check
if_error 'sha256sum fail'
# 复制安装包
mkdir -p $INSTALL_PATH/$KUBERNETES_VERSION
cp -R ./kubectl $INSTALL_PATH/$KUBERNETES_VERSION
# 添加到环境变量中
add_path $INSTALL_PATH/$KUBERNETES_VERSION

echo "install kubernetes-$KUBERNETES_VERSION success!";
