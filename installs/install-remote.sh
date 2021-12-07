#!/bin/bash
#
# 批量安装到远程服务器中

# 参数信息配置
SHELL_RUN_DESCRIPTION='远程批量安装'
DEFINE_TOOL_PARAMS="
[-d, --remote-dir='~/shell/'] 远程执行目录，shell脚本会复制到这个目录下并进行安装
#在进行安装前需要保证目录可用空间，空间不足会造成安装失败
[-s, --skip-local] 跳过本地安装，默认本地先安装，安装完后再安装远程，避免并行安装复制缺失文件
[-u, --uncopy-temp] 不复制安装目录，所以远程服务重新下载安装
[--disabled-expect] 禁止使用expect工具自动输入密码
#禁止后需要手动输入密码多次方可进行安装
[--disabled-sshkey] 禁止使用证书登录，证书登录可以减少密码输入次数
"
SHELL_RUN_HELP='
3、远程安装依赖三个工具 ssh scp ，脚本会自动安装。
4、远程安装流程：证书处理、创建目录、复制脚本、执行安装。每个环节均有可能输入密码
5、证书不建议设置密码，否则证书使用意义不大
6、使用远程安装时不可另外执行本地批量安装并行操作，会影响远程安装复制文件导致安装失败
'
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/install-batch.sh || exit
if [ -z "$ARGV_skip_local" ];then
    info_msg '本机批量安装'
    read_config install install_server
fi
# 安装必需工具
tools_install ssh scp
if [ -z "$ARGV_disabled_expect" ];then
    tools_install expect
fi
# 生成证书
if [ -z "$ARGV_disabled_sshkey" -a ! -e ~/.ssh/id_rsa.pub ];then
    info_msg '当前账号无证书，即将生成证书用于登录远程服务器'
    run_msg "ssh-keygen -t rsa"
    ssh-keygen -t rsa <<EOF



EOF
fi
if ! if_command ifconfig;then
    packge_manager_run install net-tools
fi
# 获取证书路径
SSH_KEY_PATH=`stat -c '%n' ~/.ssh/id_rsa.pub`
# 远程安装服务
# @command ssh_install_server $host [$password] [$user]
# @param $host          要连接的服务器
# @param $password      服务器登录密码，本地时不需要，如果服务器已经配置好证书登录也不需要传或传空
# @param $user          服务器登录用户名，转为为root
# return 1|0
ssh_install_server(){
    # 判断是否为本机
    if [[ "$1" == 127.0.0.1|localhost ]] || ifconfig|grep -q "$1";then
        warn_msg "远程地址是本地服务器：$1 ，跳过"
        return 1
    fi
    info_msg "$1 远程服务器安装"
    local SSH_USER=${3-root} KEYGEN_HAS=''
    if ! ssh -o ConnectTimeout=30 -o PasswordAuthentication=no -o StrictHostKeyChecking=no -n $SSH_USER@$1 2>&1 >/dev/null; then
        if [ -z "$2" ];then
            warn_msg "服务器 $SSH_USER@$1 未配置密码，且无证书登录，无法进行远程操作安装"
            return 1
        fi
        if [ -z "$ARGV_disabled_sshkey" ];then
            info_msg "复制 ssh-key 证书到 $SSH_USER@$1"
            run_msg "ssh-copy-id -i $SSH_KEY_PATH $SSH_USER@$1"
            if [ -z "$ARGV_disabled_expect" ];then
                expect <<CMD
set timeout 30
spawn ssh-copy-id -i $SSH_KEY_PATH $SSH_USER@$1
expect "*password*" {send "$2\r"; exp_continue}
CMD
            else
                ssh-copy-id -i $SSH_KEY_PATH $SSH_USER@$1
            fi
            if [ $? != '0' ];then
                warn_msg "证书复制失败"
            else
                KEYGEN_HAS=1
            fi
        fi
    else
        KEYGEN_HAS=1
    fi
    if [ "$KEYGEN_HAS" = '1' ] && ! ssh -o ConnectTimeout=30 -o PasswordAuthentication=no -n $SSH_USER@$1 2>&1 >/dev/null; then
        warn_msg "ssh登录失败，请核对信息：$SSH_USER@$1"
        return 1
    fi
    if [ -z "$ARGV_disabled_expect" -a "$KEYGEN_HAS" = '1' ];then
        info_msg "即将通过 expect 调用以下命令"
        run_msg "ssh $SSH_USER@$1 -C 'mkdir -p $ARGV_remote_dir'"
        run_msg "scp -r $SHELL_WROK_BASH_PATH $SSH_USER@$1:$ARGV_remote_dir"
        run_msg "ssh $SSH_USER@$1 -C 'nohup bash $ARGV_remote_dir/installs/install-batch.sh &' &"
        expect <<CMD
spawn ssh $SSH_USER@$1 -C 'mkdir -p $ARGV_remote_dir'
expect "*password*" {send "$2\r"; exp_continue}
spawn scp -r -f $SHELL_WROK_BASH_PATH $SSH_USER@$1:$ARGV_remote_dir
expect "*password*" {send "$2\r"; exp_continue}
spawn ssh $SSH_USER@$1 -C 'nohup bash $ARGV_remote_dir/installs/install-batch.sh &' &
expect "*password*" {send "$2\r"; exp_continue}
CMD
    else
        run_msg "ssh $SSH_USER@$1 -C 'mkdir -p $ARGV_remote_dir'"
        ssh $SSH_USER@$1 -C 'mkdir -p $ARGV_remote_dir'
        run_msg "scp -r $SHELL_WROK_BASH_PATH $SSH_USER@$1:$ARGV_remote_dir"
        scp -r $SHELL_WROK_BASH_PATH $SSH_USER@$1:$ARGV_remote_dir
        run_msg "ssh $SSH_USER@$1 -C 'nohup bash $ARGV_remote_dir/installs/install-batch.sh &' &"
        ssh $SSH_USER@$1 -C 'nohup bash $ARGV_remote_dir/installs/install-batch.sh &' &
    fi
    return $?
}
# 开始安装
read_config host ssh_install_server
