#!/bin/bash
#
# 批量安装到远程服务器中

# 参数信息配置
SHELL_RUN_DESCRIPTION='远程批量安装'
DEFINE_TOOL_PARAMS="
[remote-match]匹配要安装的远程服务器配置名
#允许使用正则表达式匹配
#匹配的并非远程服务器地址而是节点配置名
[-d, --remote-dir='~/shell-script/', {required}]远程服务器shell脚本保存目录
#shell脚本会复制到这个目录下并进行安装
#在进行安装前需要保证目录可用空间，空间不足会造成安装失败
[-i, --local-install='async', {required|in:async,before,skip}]本地批量安装处理
#async  异步安装远程与本地并行
#       各服务不复制安装文件
#       各服务器均需要自行下载安装包
#before 先安装本地并在安装完后再安装远程
#       安装远程时会复制安装文件
#       各服务不需要再下载相同的文件
#skip   不执行本地安装，仅执行远程安装
#       将复制安装文件致远程服务器
#       此选项不可与本地批量安装并行
#       当本地有并行安装时将终止批量安装
#执行远程批量安装时尽量避免本地另执行批量安装
#本地交叉批量安装会影响复制文件完整导致远程安装异常
[--disable-expect]禁止使用expect工具自动输入密码
#禁用后配置文件中的密码将无法自动输入并登录
[--ssh-key='~/.ssh/id_rsa.pub']指定本地登录远程服务器证书地址
#证书地址文件不存在时会自动创建
#为空时将处理证书登录和创建操作
#为空时如果已经配置好证书登录将自动使用
"
SHELL_RUN_HELP='

远程安装要求：
1、远程安装依赖三个工具 ssh scp ，脚本会自动安装。
2、远程安装流程：证书处理、创建目录、复制脚本、执行安装。每个环节均有可能输入密码
3、使用的证书不建议设置密码，否则证书登录时还需要输入密码
4、使用远程安装时不可另外执行本地批量安装并行操作，会影响远程安装复制文件导致安装失败
'
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/install-batch.sh || exit
# 开始远程安装服务
# @command start_ssh_install $item_name $item_value
# @param $item_name         配置区块内项名，远程节点名
# @param $item_value        配置区块内项值，远程节点信息
# return 1|0
start_ssh_install(){
    # 解析远程服务器配置信息
    local REMOTE_INFO=($2)
    if [ "${#REMOTE_INFO[@]}" = '0' ];then
        warn_msg "$1 远程配置节点信息为空，跳过安装"
        return 1
    fi
    info_msg "${REMOTE_INFO[0]} 远程服务器安装"
    local SSH_USER=root SSH_HOST="${REMOTE_INFO[0]}" SSH_PORT=22 SSH_PASSWORD="${REMOTE_INFO[1]}" SSH_ROOT_PASSWORD="${REMOTE_INFO[2]}"
    if [[ -z "$ARGV_disable_expect" && "$SSH_PASSWORD$SSH_ROOT_PASSWORD" =~ '"' ]];then
        warn_msg "$1 远程配置节点使用 expect 密码不能包含双引号，跳过安装"
        return 1
    fi
    # 获取指定登录用户名
    if [[ "${REMOTE_INFO[0]}" =~ .+@.+ ]];then
        SSH_USER="${REMOTE_INFO[0]%%@*}"
        SSH_HOST="${SSH_HOST#*@}"
    fi
    if [[ -z "$SSH_USER" ]];then
        warn_msg "$1 远程配置节点登录用户名为空，跳过安装"
        return 1
    fi
    # 获取指定登录端口号
    if [[ "${REMOTE_INFO[0]}" =~ .+:.+ ]];then
        SSH_PORT="${REMOTE_INFO[0]##*:}"
        SSH_HOST="${SSH_HOST%*:}"
    fi
    if [[ -z "$SSH_PORT" || ! "$SSH_PORT" =~ ^([0-9]|[1-9][0-9]{0,5})$ ]] || (( SSH_PORT >= 65536 || SSH_PORT == 0 ));then
        warn_msg "$1 远程配置节点端口号错误：$SSH_PORT，跳过安装"
        return 1
    fi
    if [[ -z "$SSH_HOST" ]];then
        warn_msg "$1 远程配置节点登录地址为空，跳过安装"
        return 1
    fi
    local LOG_FILE EXPECT_PASSWORD START_TIME=$(date +'%s') KEYGEN_LOGIN=1 SSH_ADDR="$SSH_USER@$SSH_HOST"
    local SSH_CHECK="ssh -q -o ConnectTimeout=15 -o PasswordAuthentication=no -o StrictHostKeyChecking=no $SSH_KEY_OPTION -p $SSH_PORT $SSH_ADDR"
    # 证书登录尝试
    if ! $SSH_CHECK; then
        if (( START_TIME + 14 < $(date +'%s') ));then
            warn_msg "$1 远程配置节点连接超时（15秒）或网速过慢，跳过安装"
            return 1
        fi
        warn_msg "$1 远程配置节点证书登录失败"
        # 证书处理
        if [ -n "$SSH_KEY_OPTION" ];then
            info_msg "尝试复制 ssh-key 证书到 $1 服务器"
            if [ -z "$ARGV_disable_expect" -a -n "$SSH_PASSWORD" ];then
                info_msg "通过 expect 自动完成证书复制"
                expect_password EXPECT_PASSWORD "$SSH_PASSWORD"
                expect <<CMD
spawn ssh-copy-id $SSH_KEY_OPTION "-p $SSH_PORT $SSH_ADDR"
$EXPECT_PASSWORD
CMD
            else
                run_msg ssh-copy-id $SSH_KEY_OPTION "-p $SSH_PORT $SSH_ADDR"
            fi
        else
            info_msg "没有指定证书，跳过证书登录处理"
        fi
        if $SSH_CHECK; then
            info_msg "证书复制成功"
        else
            warn_msg "证书复制失败"
            KEYGEN_LOGIN=0
        fi
    fi
    # 基本命令定义
    local SCP_COMMAND="scp -r -f -P $SSH_PORT $COPY_REMOTE_FILE $SSH_ADDR:$ARGV_remote_dir"
    if [ "$SSH_USER" = root ];then
        local MKDIR_COMMAND="ssh $SSH_ADDR -C 'mkdir -p $ARGV_remote_dir'"
        local BASH_COMMAND="ssh $SSH_ADDR -C 'cd $ARGV_remote_dir && tar -xzf $COPY_REMOTE_FILE && bash ./installs/install-batch.sh \"$ARGU_name\" &'"
    else
        local MKDIR_COMMAND="ssh $SSH_ADDR -C 'echo \"mkdir -p $ARGV_remote_dir && chown -R $SSH_USER:$SSH_USER $ARGV_remote_dir\"|sudo -u root -s'"
        local BASH_COMMAND="ssh $SSH_ADDR -C 'cd $ARGV_remote_dir && tar -xzf $COPY_REMOTE_FILE && sudo -u root bash $ARGV_remote_dir/installs/install-batch.sh \"$ARGU_name\"'"
    fi
    install_log_file LOG_FILE "$1-${SSH_HOST}"
    # 选项执行方式
    if [ -n "$ARGV_disable_expect" ] || [ "$KEYGEN_LOGIN" = '1' -a "$SSH_USER" = root ] || [ "$SSH_USER" != root -a -z "$SSH_ROOT_PASSWORD" ];then
        run_msg "$MKDIR_COMMAND && 
$SCP_COMMAND && 
$BASH_COMMAND > &"
    else
        info_msg "通过 expect 自动完成远程复制和安装"
        local EXPECT_ROOT_PASSWORD
        if [ "$KEYGEN_LOGIN" = '0' -a -z "$EXPECT_PASSWORD" ];then
            expect_password EXPECT_PASSWORD "$SSH_PASSWORD"
        fi
        if [ "$SSH_USER" != root ];then
            expect_password EXPECT_ROOT_PASSWORD "$SSH_ROOT_PASSWORD"
        fi
        expect & <<CMD
spawn $MKDIR_COMMAND
$EXPECT_PASSWORD
$EXPECT_ROOT_PASSWORD
spawn $SCP_COMMAND
$EXPECT_PASSWORD
spawn $BASH_COMMAND
$EXPECT_PASSWORD
$EXPECT_ROOT_PASSWORD
CMD
    fi
}
# 获取 expect 密码输入操作
# @command expect_password $set_value $password
# @param $set_value         写入变量名
# @param $password          要输入的密码
# return 1|0
expect_password(){
    eval "$1='expect {
    \"*yes/no\" { send \"$2\r\"; exp_continue }
    \"*password:\" { send \"$2\r\" }
}'"
}
# 安装必需工具
tools_install ssh scp
if [ -z "$ARGV_disable_expect" ];then
    tools_install expect
fi
# 生成证书
if [ -n "$ARGV_ssh_key" ];then
    SSH_KEY_DIR=$(dirname $ARGV_ssh_key)
    if [ ! -d $SSH_KEY_DIR ];then
        mkdirs $SSH_KEY_DIR
        chmod 700 $SSH_KEY_DIR
    fi
    SSH_KEY_FILE=$(cd $SSH_KEY_DIR; pwd)/$(basename "$ARGV_ssh_key")
    if [ ! -e "$SSH_KEY_FILE" ];then
        info_msg "当前账号无证书，生成证书保存到：$SSH_KEY_FILE"
        ssh-keygen -t rsa -f "$SSH_KEY_FILE" -P ''
        if_error "证书生成失败"
    fi
    # 生成证书使用选项
    SSH_KEY_OPTION="-i '$SSH_KEY_FILE'"
fi
# 本地安装方式处理
TAR_OPTIONS=''
case "$ARGV_local_install" in
    async)
        start_install
        TAR_OPTIONS='--exclude=./temp'
    ;;
    before)
        start_install 1
    ;;
    skip)
        if has_run_shell "*-install"; then
            error_exit "检测到本地已经有安装脚本运行中"
        fi
        info_msg '跳过本机批量安装'
    ;;
esac
cd $SHELL_WROK_BASH_PATH
COPY_REMOTE_FILE=./temp/remote-shell.tar.gz
# 压缩脚本及相关文件
info_msg "压缩脚本及相关文件到：$COPY_REMOTE_FILE"
run_msg "tar -czf $COPY_REMOTE_FILE $TAR_OPTIONS ./"
if_error "压缩文件失败，请确认权限和磁盘空间"
# 循环远程配置数据并执行安装
each_conf start_ssh_install remote
run_msg "rm -f $COPY_REMOTE_FILE"
# 最后还得等待所有子进程结束
info_msg "等待所有批量安装子进程结束"
wait
