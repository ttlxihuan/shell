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
# CentOS 6.4+
# Ubuntu 16.04+
#
# 官方地址：https://kubernetes.io/zh/
# 官方文档地址：https://kubernetes.io/zh/docs/home/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '1.19.1' "https://dl.k8s.io/release/stable.txt" 'v\d+\.\d+\.\d+'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 1
# ************** 编译安装 ******************
chdir $INSTALL_NAME
# 下载kubernetes包
download_file https://dl.k8s.io/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl
download_file https://dl.k8s.io/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl.sha256
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
if_error 'sha256sum 验证失败'

# 复制安装包并创建用户
copy_install kubectl '' ./kubectl ./kubectl.sha256
chmod +x kubectl

# 添加到环境变量中
add_path $INSTALL_PATH$KUBERNETES_VERSION

info_msg "安装成功：kubernetes-$KUBERNETES_VERSION";
