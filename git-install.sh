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
#
# 协议使用说明：
# git 支持多种访问协议，主要有：file、ssh、http[s]、git。
#
# file 是本地文件协议，即在同一个系统内可直接通过文件路径操作，且不支持跨系统（共享目录除外）。
#   典型方式：
#       git clone /home/git/test.git
#   file方式访问版本版本不需要额外处理，创建好版本库后就可以访问。
#

# ssh 是git通过ssh登录后操作git相关命令进行处理，ssh登录必需授权登录（证书或密码）。
#   ssh典型方式：
#       git clone ssh://username@host:port/home/git/test.git
#       版本库地址标准语法是： ssh://[user@]host[:port]path  不支持相关路径
#   scp典型方式：
#       git clone username@host:test.git
#       版本库地址标准语法是： [user@]host:path  支持相关路径（相对user的工作目录，比如/home/git目录），路径前面没有/即为相对路径
#   ssh方式访问需要配置访问账号密码或者在/home/git下配置ssh证书信息，否则无法访问

# http[s]是通过http协议请求调用git相关命令进行处理，http[s]可开放或授权限制版本库。
#   典型方式：
#       git clone https://host:port/home/git/test.git
#       版本库地址标准语法是： http[s]://host[:port]path
#   http[s]方式访问一般需要三方实现，git以操作http版本库时会自动按http协议方式发送请求到远程版本库服务器，服务器通过http请求信息分析处理通过管道模式调用git相关工具完成操作。

# git是git提供的一种监听服务，默认监听端口9418，git不需要授权就可以自由访问，但需要启动git服务。
#   典型方式：
#       git clone git://host:port/home/git/test.git
#       版本库地址标准语法是： git://host[:port]path
#   git服务启动命令 git daemon --reuseaddr --base-path=这里是监听目录
#   git服务启动后还需要在每个版本库里创建git-daemon-export-ok文件，一般使用命令：touch git-daemon-export-ok
#
#
#
# 版本库勾子使用说明：
#   git提供了很多操作前后调用特定脚本，通过修改这些脚本可以改变git功能，一般修改的是推送勾子：pre-receive、post-update、update
#
#   pre-receive、post-update是在接收推送前和后调用的，当pre-receive脚本以非0状态退出则拒绝推送（可用于代码审核过滤等操作）。pre-receive、post-update在一次推送中只调用一次。
#
#   update 是每个要更新的分支执行前调用，当以非0状态退出时则拒绝当前分支推送。update脚本有三个参数：分支名，更新前版本号（SHA-1），更新后版本号（SHA-1）
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
[-d, --tool-path='']管理工具工作目录，最好是绝对路径，默认安装在/home/git
[-p, --ssh-password='']指定ssh账号密码，不指定则不生成。默认会创建git账号用于 ssh://git@ip/path 访问，但需要通过证书或密码访问。
[-P, --random-ssh-password='']随机生成指定长度ssh账号密码，长度范围是1~99位。如果已经指定密码此参数无效。
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
# 密码处理
if [ -n "$ARGV_ssh_password" ]; then
    GIT_SSH_PASSWORD="$ARGV_ssh_password"
elif [ -n "$ARGV_random_ssh_password" ]; then
    if ! [[ "$ARGV_random_ssh_password" =~ ^[1-9][0-9]*$ ]];then
        error_exit "--random-ssh-password must be an integer, $ARGV_random_ssh_password"
    fi
    if (($ARGV_random_ssh_password < 0 || $ARGV_random_ssh_password > 100));then
        error_exit "--random-ssh-password range is 1~99, $ARGV_random_ssh_password"
    fi
    # 生成随机密码
    random_password GIT_SSH_PASSWORD $ARGV_random_ssh_password
else
    GIT_SSH_PASSWORD=''
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
add_user git $INSTALL_PATH$GIT_VERSION/bin/git-shell $GIT_SSH_PASSWORD

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
    if ! if_command gitlab-ctl;then
        if_error "install gitlab fail!"
    fi
    # 修改配置
    sed -ir "s/^\(external_url \).*/\1'http:\/\/127.0.0.1'/" /etc/gitlab/gitlab.rb
    echo 'gitlab host: http://127.0.0.1'
    # 配置处理
    gitlab-ctl configure
    # 启动服务
    gitlab-ctl start
    echo "install gitlab success!"
fi
