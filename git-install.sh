#!/bin/bash
#
# git快速编译安装shell脚本
#
# 安装命令
# bash git-install.sh new [--tool=str] [--tool-path=str]
# bash git-install.sh $verions_num [--tool=str] [--tool-path=str]
# 
# 查看最新版命令
# bash git-install.sh
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
# 定义安装参数
DEFINE_INSTALL_PARAMS="
[-t, --tool='']安装管理工具，目前支持 gitolite 和 gitlab
[-p, --tool-path='']管理工具工作目录，最好是绝对路径，默认安装在/home/git
"
# 初始化安装
init_install GIT_VERSION DEFINE_INSTALL_PARAMS
# 安装参数处理
if [ -n "$ARGV_tool" ];then
    if [[ "$ARGV_tool" =~ ^git(olite|lab)$ ]]; then
        if [ -n "$ARGV_tool_path" ]; then
            TOOL_WORK_PATH="$ARGV_tool_path"
        else
            TOOL_WORK_PATH='/home/git'
        fi
    else
        error_exit "$ARGV_tool unknown tool"
    fi
fi
# ************** 编译项配置 ******************
# 编译初始选项（这里的指定必需有编译项）
CONFIGURE_OPTIONS="--prefix=$INSTALL_PATH$GIT_VERSION"
# 编译增加项（这里的配置会随着编译版本自动生成编译项）
ADD_OPTIONS=$ARGV_options
# ************** 编译安装 ******************
# 下载git包
download_software https://mirrors.edge.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz
# 解析选项
parse_options CONFIGURE_OPTIONS $ADD_OPTIONS
# 安装依赖
echo "install dependence"
packge_manager_run install -LIBXML2_DEVEL_PACKGE_NAMES -PERL_DEVEL_PACKGE_NAMES

# msgfmt命令在gettext包中
if ! if_command msgfmt;then
    packge_manager_run install -GETTEXT_DEVEL_PACKGE_NAMES
    if ! if_command msgfmt;then
        # 暂存编译目录
        GIT_CONFIGURE_PATH=`pwd`
        # 找不到就编译安装
        # 安装gettext
        # 获取最新版
        get_version GETTEXT_VERSION https://ftp.gnu.org/pub/gnu/gettext 'gettext-\d+(\.\d+){2}\.tar\.gz'
        echo "install gettext-$GETTEXT_VERSION"
        # 下载
        download_software https://ftp.gnu.org/pub/gnu/gettext/gettext-$GETTEXT_VERSION.tar.gz
        # 编译安装
        configure_install --prefix=$INSTALL_BASE_PATH/gettext/$GETTEXT_VERSION
        cd $GIT_CONFIGURE_PATH
    fi
fi

# 编译安装
configure_install $CONFIGURE_OPTIONS

# 创建用户组
add_user git bash

# 添加执行文件连接
add_local_run $INSTALL_PATH$GIT_VERSION/bin/ 'git' 'git-receive-*' 'git-upload-*'

if [ -n "$ARGV_tool" ];then
    mkdirs "$TOOL_WORK_PATH" git
fi

echo "install git-$GIT_VERSION success!"

if [ "$ARGV_tool" = "gitolite" ]; then
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

if [ "$ARGV_tool" = "gitlab" ]; then
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
