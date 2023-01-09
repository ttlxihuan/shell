#!/bin/bash
#
# jenkins快速安装shell脚本
#
# 安装命令
# bash jenkins-install.sh new
# bash jenkins-install.sh $verions_num
# 
# 查看最新版命令
# bash jenkins-install.sh
#
# 可运行系统：
# CentOS 6.4+
# Ubuntu 16.04+
#
# 官方地址：https://www.jenkins.io/
# 中文文档：https://www.jenkins.io/zh/doc/
#
# 建议安装较新版，内部很多插件不兼容低版本，安装版本越新越好
# 如果默认界面非中文可安装插件 Localization: Chinese (Simplified) ，安装后需要重启jenkins服务
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 定义安装参数
DEFINE_RUN_PARAMS="
[-p, --port='8080', {required|int:0,65535}]服务监听端口号
"
# 加载基本处理
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../../includes/install.sh || exit
# 初始化安装
init_install '2.0.0' "https://get.jenkins.io/war-stable/" '>\d+\.\d+\.\d+/<'
#  限制空间大小（G）：编译目录、安装目录、内存
install_storage_require 1 1 2
# ************** 编译安装 ******************
# 下载jenkins包
download_file "https://get.jenkins.io/war-stable/$JENKINS_VERSION/jenkins.war" jenkins.war

# 暂存编译目录
JENKINS_CONFIGURE_PATH=$(pwd)

# 不同的版本要求java版本不一样
if if_version "$JENKINS_VERSION" '>=' '2.361.1';then
    # Java 11 or Java 17
    MIN_JAVA_VERSION=11.0.0
    MAX_JAVA_VERSION=18.0.0
elif if_version "$JENKINS_VERSION" '>=' '2.361.1';then
    # Java 8 or Java 11
    MIN_JAVA_VERSION=1.8.0
    MAX_JAVA_VERSION=12.0.0
else
    # Java 8
    MIN_JAVA_VERSION=1.8.0
    MAX_JAVA_VERSION=1.9.0
fi

# 安装验证 java，过高的版本可能会出现运行异常
# 建议安装java 8
install_java $MIN_JAVA_VERSION $MAX_JAVA_VERSION

cd $JENKINS_CONFIGURE_PATH

# 复制安装包并创建用户
copy_install jenkins '' ./jenkins.war
mkdirs /home/jenkins jenkins

# 添加服务配置
SERVICES_CONFIG=()
SERVICES_CONFIG[$SERVICES_CONFIG_START_RUN]="nohup java -Dhudson.model.DownloadService.noSignatureCheck=true -jar ./jenkins.war --httpPort=$ARGV_port --prefix=/jenkins --controlPort=8088 >/dev/null 2>/dev/null &"
SERVICES_CONFIG[$SERVICES_CONFIG_USER]="jenkins"
SERVICES_CONFIG[$SERVICES_CONFIG_PID_RUN]="ps ax|grep './jenkins.war'|grep -oP '[0-9]+'|head -n 1"

# 服务并启动服务
add_service SERVICES_CONFIG

get_ip
info_msg "访问地址：http://$SERVER_IP:8083/jenkins"
info_msg "初始账号 admin"
info_msg "初始密码 $(cat /home/jenkins/.jenkins/secrets/initialAdminPassword)"

info_msg "安装成功：jenkins-$JENKINS_VERSION";
