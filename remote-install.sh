#!/bin/bash
#
# 批量安装到远程服务器中
# 受 install.conf 配置文件影响
# 

source basic.sh
source install.sh
# 安装必需工具
tools_install ssh expect scp
# 生成证书
if [ ! -e ~/.ssh/id_rsa.pub ]; then
    ssh-keygen -t rsa
fi
# 获取证书路径
SSH_KEY_PATH=`stat -c '%n' ~/.ssh/id_rsa.pub`
# 安装服务
ssh_install_server(){
    echo -e "\033[31m install to $1 \033[0m"
    # 判断是否为本机
    if test "$1" = '127.0.0.1' || test "$1" = 'localhost';then
        read_config install install_server
    else
        local SSH_USER='root'
        if [ -n "$3" ];then
            SSH_USER="$3"
        fi
        if ! ssh -o ConnectTimeout=30 -o PasswordAuthentication=no -o StrictHostKeyChecking=no -n $SSH_USER@$1 2>&1 &>/dev/null; then
            echo "copy ssh-key to $SSH_USER@$1"
            expect <<CMD
    set timeout 30
    spawn ssh-copy-id -i $SSH_KEY_PATH $SSH_USER@$1
    expect "*password*" {send "$2\r"; exp_continue}
CMD
        fi
        if ! ssh -o ConnectTimeout=30 -o PasswordAuthentication=no -n $SSH_USER@$1 2>&1 &>/dev/null; then
            echo "ssh login fail"
            return 1
        fi
        echo "copy file ..."
        ssh $SSH_USER@$1 -C 'mkdir -p ~/install-shell'
        scp -r $COPY_FILES $SSH_USER@$1:./install-shell/
        echo "ssh install ..."
        ssh $SSH_USER@$1 -C 'cd ~/install-shell; nohup bash ./install.sh &' &
    fi
    return 0
}
# 提取安装的脚本
copy_server(){
    echo -n " ./$1-install.sh"
}
COPY_FILES="./install.sh ./install.conf ./basic.sh"`read_config install copy_server`
# 开始安装
read_config host ssh_install_server
