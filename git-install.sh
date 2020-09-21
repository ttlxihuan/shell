#!/bin/bash
#
# git快速编译安装shell脚本
#
# 安装命令
# bash git-install.sh new [tool] [tool_path]
# bash git-install.sh $verions_num [tool] [tool_path]
# 
# 查看最新版命令
# bash git-install.sh
#
#  命令参数说明
#  $1 指定安装版本，如果不传则获取最新版本号，为 new 时安装最新版本
#  $2 安装管理工具，目前支持 gitolite 和 gitlab
#  $3 管理工具工作目录，最好是绝对路径，默认安装在/home/git
#
# 可运行系统：
# CentOS 5+
# Ubuntu 15+
#
# 下载地址
# https://mirrors.edge.kernel.org/pub/software/scm/git/
#
####################################################################################
##################################### 安装处理 #####################################
####################################################################################
# 加载基本处理
source basic.sh
# 获取工作目录
INSTALL_NAME='git'
# 获取版本配置
VERSION_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/"
VERSION_MATCH='git-\d+\.\d+\.\d+\.tar\.gz'
VERSION_RULE='\d+\.\d+\.\d+'
# 安装最小版本
GIT_VERSION_MIN='1.9.0'
# 初始化安装
init_install GIT_VERSION "$1"
if [ -n "$2" ];then
    if [[ "$2" =~ ^git(olite|lab)$ ]]; then
        if [ -n "$3" ]; then
            TOOL_WORK_PATH="$3"
        else
            TOOL_WORK_PATH='/home/git'
        fi
    else
        error_exit "$2 unknown tool"
    fi
fi
# ************** 编译项配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$GIT_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=''
# ************** 编译安装 ******************
# 下载git包
download_software https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "install dependence"
packge_manager_run install -LIBXML2_DEVEL_PACKGE_NAMES -PERL_DEVEL_PACKGE_NAMES

# 编译安装
configure_install $CONFIGURE_OPTIONS

# 创建用户组
add_user git

if [ -n "$2" ];then
    mkdirs "$TOOL_WORK_PATH" git
fi

echo "install git-$GIT_VERSION success!"

if [[ "$2" == "gitolite" ]]; then
    # 安装 gitolite
    echo 'install gitolite'
    # 下载gitolite包
    download_software https://github.com/sitaramc/gitolite/archive/master.zip gitolite-master
    # yum install -y 'perl(Data::Dumper)'
    if [ ! -e "$TOOL_WORK_PATH/gitolite-admin.pub" ]; then
        if [ ! -e "~/.ssh/id_rsa" ];then
            ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''
        fi
        cp ~/.ssh/id_rsa.pub $TOOL_WORK_PATH/gitolite-admin.pub
        chown git:git $TOOL_WORK_PATH/gitolite-admin.pub
    fi
    # 创建快捷方式，这步很重要，否则gitolite无法正常工作
    ln -sv $INSTALL_BASE$GIT_VERSION/bin/git /bin/git
    mkdirs "$TOOL_WORK_PATH/gitolite" git
    packge_manager_run install 'perl(Data::Dumper)'
    echo "./install -to $TOOL_WORK_PATH/gitolite"
    sudo -u git ./install -to $TOOL_WORK_PATH/gitolite
    if_error "gitolite install fail!"
    cd $TOOL_WORK_PATH/gitolite
    echo "./gitolite setup -pk gitolite-admin.pub"
    sudo -u git ./gitolite setup -pk $TOOL_WORK_PATH/gitolite-admin.pub
    if [ -d "$TOOL_WORK_PATH/repositories" ]; then
        echo 'admin repository'
        SERVER_IP=`ifconfig|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o -m 1|head -n 1`
        echo "git clone git@\$SERVER_IP:gitolite-admin"
        echo "install gitolite success!"
    else
        echo 'gitolite install fail!'
    fi
fi

if [[ "$2" == "gitlab" ]]; then
    # 安装 gitlab
    if [ ! -e 'gitlab.sh' ];then
        if [[ "$PACKGE_MANAGER_INDEX" == 0 ]];then
            wget --no-check-certificate -T 7200 -O gitlab.sh https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.rpm.sh
        else
            wget --no-check-certificate -T 7200 -O gitlab.sh https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh
        fi
    fi
    if_error "gitlab.sh download fail!"
    bash gitlab.sh
    packge_manager_run install gitlab-ee
    if_error "install gitlab fail!"
    echo "install gitlab success!"
fi
