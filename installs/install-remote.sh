#!/bin/bash
#
# 批量安装到远程服务器中
# 远程登录小异常
# 1、登录指定账号时命令行显示的类似 -bash-4.1# 而不是类似 [root@localhost ~]# ，多数是home目录丢失 .bash* 相关文件
#     修复命令：  cp -p /etc/skel/.bash* ~/
# 2、ssh登录有明显等待时长且显示：/usr/bin/xauth:  timeout in locking authority file /root/.Xauthority
#   提示这个基本是权限限制，需要排查用户目录（即 ~ ）是否存在且用户组是否与用户匹配，是否开放了用户组的读写权限
#   以上排查均通过可能是SELinux（基于red hat linux内核）或AppArmor（ubuntu或suse等）访问控制限制掉，直接关掉存在安全风险
#   SELinux 查看命令: sestatus  在Current mode选项上有三种值：Enforcing（强制严格权限） 、Permissive（兼容权限） 、Disabled（禁用）。通过 setenforce 命令进行修改，具体修改参数可通过帮助参数了解 
#   AppArmor 查看命令：apparmor_status 
#   用户目录（即 ~ ）权限修改: chmod 0700 ~ && chmod u+rw ~/.Xauthority
#

# 参数信息配置
SHELL_RUN_DESCRIPTION='远程批量安装'
DEFINE_TOOL_PARAMS="
[remote-match]匹配要安装的远程服务器配置名
#允许使用正则表达式匹配
#匹配的并非远程服务器地址而是节点配置名
[-d, --remote-dir='~/shell-script/', {required}]远程服务器shell脚本保存目录
#shell脚本会复制到这个目录下并进行安装
#此目录需要保证登录账号有读写操作权限
#在进行安装前需要保证目录可用空间，空间不足会造成安装失败
[-i, --local-install='async', {required|in:async,skip}]本地批量安装处理
#async  异步安装远程与本地并行
#       各服务不复制安装文件
#       各服务器均需要自行下载安装包
#skip   不执行本地安装，仅执行远程安装
#       将复制安装文件致远程服务器
#       此选项不可与本地批量安装并行
#       当本地有并行安装时将终止批量安装
#执行远程批量安装时尽量避免本地另执行批量安装
#本地交叉批量安装会影响复制文件完整导致远程安装异常
[-E, --disable-expect]禁止使用expect工具自动输入密码
#禁用后配置文件中的密码将无法自动输入并登录
[--ssh-key='~/.ssh/id_rsa']指定本地登录远程服务器证书地址
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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/install-batch.sh || exit
# 开始远程安装服务
# @command start_ssh_install $item_name $item_value
# @param $item_name         配置区块内项名，远程节点名
# @param $item_value        配置区块内项值，远程节点信息
# return 1|0
start_ssh_install(){
    if [ -n "$ARGU_remote_match" ] && ! printf '%s' "$1"|grep -qP "$ARGU_remote_match";then
        return
    fi
    # 解析远程服务器配置信息
    local REMOTE_INFO=($2)
    if [ "${#REMOTE_INFO[@]}" = '0' ];then
        warn_msg "$1 远程配置节点信息为空，跳过安装"
        return 1
    fi
    tag_msg "$1 = ${REMOTE_INFO[0]#*@}"
    local SSH_USER=root SSH_HOST="${REMOTE_INFO[0]}" SSH_PORT=22 SSH_PASSWORD="${REMOTE_INFO[1]}" SSH_ROOT_PASSWORD="${REMOTE_INFO[2]}"
    if [[ -z "$ARGV_disable_expect" && "$SSH_PASSWORD$SSH_ROOT_PASSWORD" =~ '"' ]];then
        warn_msg "节点账号密码不能包含双引号，跳过安装"
        return 1
    fi
    # 获取指定登录用户名
    if [[ "${REMOTE_INFO[0]}" =~ .+@.+ ]];then
        SSH_USER="${REMOTE_INFO[0]%%@*}"
        SSH_HOST="${SSH_HOST#*@}"
    fi
    if [[ -z "$SSH_USER" ]];then
        warn_msg "节点登录用户名为空，跳过安装"
        return 1
    fi
    # 获取指定登录端口号
    if [[ "${REMOTE_INFO[0]}" =~ .+:.+ ]];then
        SSH_PORT="${REMOTE_INFO[0]##*:}"
        SSH_HOST="${SSH_HOST%*:}"
    fi
    if [[ -z "$SSH_PORT" || ! "$SSH_PORT" =~ ^([0-9]|[1-9][0-9]{0,5})$ ]] || (( SSH_PORT >= 65536 || SSH_PORT == 0 ));then
        warn_msg "节点端口号错误：$SSH_PORT，跳过安装"
        return 1
    fi
    if [[ -z "$SSH_HOST" ]];then
        warn_msg "节点登录地址为空，跳过安装"
        return 1
    fi
    local LOG_FILE EXPECT_PASSWORD START_TIME=$(date +'%s') KEYGEN_LOGIN=1 SSH_ADDR="$SSH_USER@$SSH_HOST"
    local SSH_CONNECT SSH_HOST_OPTION="-p $SSH_PORT \"$SSH_ADDR\""
    local SSH_CHECK="ssh -o ConnectTimeout=15 -o PasswordAuthentication=no -o StrictHostKeyChecking=no -n $SSH_KEY_OPTION $SSH_HOST_OPTION 2>&1"
    SSH_CONNECT="$(eval $SSH_CHECK)"
    # 证书登录尝试
    if [ $? != '0' ]; then
        if [[ "$SSH_CONNECT" != *"Permission denied"* ]];then
            warn_msg "$1 远程配置节点网络不通，请确认远程服务器host地址、sshd服务、端口号是否正确，sshd服务快捷安装命令： yum install sshd 或 apt install openssh-server 。跳过安装"
            return 1
        fi
        warn_msg "$1 远程配置节点没有配置证书登录"
        # 证书处理
        if [ -n "$SSH_KEY_OPTION" ];then
            # 注意：ssh-copy-id 命令是一个shell脚本，一般在 /usr/bin/ssh-copy-id
            # 因为没有提供过多的ssh参数选项所以只能通过地址打包参数
            local COPY_KEY_OPTION="$SSH_KEY_OPTION \"-p $SSH_PORT $SSH_ADDR\""
            info_msg "尝试复制 ssh-key 证书到 $1 服务器，可能要求输入密码"
            if [ -z "$ARGV_disable_expect" -a -n "$SSH_PASSWORD" ];then
                expect_password EXPECT_PASSWORD "$SSH_PASSWORD"
                # expect不支持单引号字符串，必需使用双引号字符串
                expect -d <<EOF
set timeout 30
spawn ssh-copy-id $COPY_KEY_OPTION
$EXPECT_PASSWORD
EOF
            else
                ssh-copy-id $COPY_KEY_OPTION
            fi
            if eval $SSH_CHECK >/dev/null; then
                info_msg "证书复制成功"
            else
                warn_msg "证书复制失败"
                KEYGEN_LOGIN=0
            fi
        else
            info_msg "没有指定证书，跳过证书登录处理"
        fi
    fi
    SSH_HOST_OPTION="$SSH_KEY_OPTION $SSH_HOST_OPTION"
    # 基本命令定义
    # expect不支持单引号字符串，必需使用双引号字符串
    local MKDIR_COMMAND="mkdir -p $ARGV_remote_dir" SCP_COMMAND="scp -r $SSH_KEY_OPTION -P $SSH_PORT \"$COPY_REMOTE_FILE\" $SSH_ADDR:$ARGV_remote_dir"
    local INSTALL_COMMAND="cd $ARGV_remote_dir && tar -xzf $(basename $COPY_REMOTE_FILE) &&"
    if [ "$SSH_USER" != root ];then
        INSTALL_COMMAND="$INSTALL_COMMAND sudo"
    fi
    INSTALL_COMMAND="$INSTALL_COMMAND bash ./installs/install-batch.sh '$ARGU_name'"
    # 验证安装结果
    if [ -n "$ARGV_check_install" ];then
        INSTALL_COMMAND="$INSTALL_COMMAND -c"
    fi
    # 拼装执行命令
    local SSH_INSTALL_COMMAND SSH_MKDIR_COMMAND="ssh $SSH_HOST_OPTION \"$MKDIR_COMMAND\""
    if [ "$SSH_USER" = root ];then
        SSH_INSTALL_COMMAND="ssh $SSH_HOST_OPTION \"$INSTALL_COMMAND\""
    else
        SSH_INSTALL_COMMAND="ssh -t $SSH_HOST_OPTION \"$INSTALL_COMMAND\""
    fi
    # 选项执行方式
    if [ -n "$ARGV_disable_expect" ] || [ "$KEYGEN_LOGIN" = '1' -a "$SSH_USER" = root ] || [ "$SSH_USER" != root -a -z "$SSH_ROOT_PASSWORD" ];then
        eval "$SSH_MKDIR_COMMAND && $SCP_COMMAND && $SSH_INSTALL_COMMAND"
    else
        local EXPECT_ROOT_PASSWORD
        if [ "$KEYGEN_LOGIN" = '0' ];then
            [ -z "$EXPECT_PASSWORD" ] && expect_password EXPECT_PASSWORD "$SSH_PASSWORD"
        else
            EXPECT_PASSWORD=''
        fi
        if [ "$SSH_USER" != root ];then
            expect_password EXPECT_ROOT_PASSWORD "$SSH_ROOT_PASSWORD"
        fi
        # expect -d 是调试模式，可以打印出命令输出信息和expect操作信息
        expect <<EOF
set timeout 30
spawn $SSH_MKDIR_COMMAND
$EXPECT_PASSWORD
spawn $SCP_COMMAND
$EXPECT_PASSWORD
spawn $SSH_INSTALL_COMMAND
$EXPECT_PASSWORD
$EXPECT_ROOT_PASSWORD
EOF
    fi
    [ $? != '0' ] && warn_msg "远程操作失败"
}
# 获取 expect 密码输入操作
# @command expect_password $set_value $password
# @param $set_value         写入变量名
# @param $password          要输入的密码
# return 1|0
expect_password(){
    eval "$1='expect {
        \"*yes/no*\" {
            send \"yes\r\";
            exp_continue;
        }
        \"*password*\" {
            send \"$2\r\";
            exp_continue;
        }
}'"
}
# 安装必需工具
tools_install ssh scp
if [ -z "$ARGV_disable_expect" ];then
    tools_install expect
fi
# 生成证书
if [ -n "$ARGV_ssh_key" ];then
    safe_realpath ARGV_ssh_key
    SSH_KEY_DIR=$(dirname "$ARGV_ssh_key")
    if [ ! -d "$SSH_KEY_DIR" ];then
        mkdirs "$SSH_KEY_DIR"
        chmod 0700 "$SSH_KEY_DIR"
    fi
    if [ ! -e "$ARGV_ssh_key" ];then
        info_msg "当前账号无证书，生成证书保存到：$ARGV_ssh_key"
        ssh-keygen -t rsa -f "$ARGV_ssh_key" -P ''
        if_error "证书生成失败"
    fi
    # 修改权限
    chmod 0600 "$ARGV_ssh_key.pub"
    # 生成证书使用选项
    SSH_KEY_OPTION="-i $ARGV_ssh_key"
fi
cd $SHELL_WROK_BASH_PATH
COPY_REMOTE_FILE=./temp/remote-shell.tar.gz
EXCLUDE_OPTIONS="--exclude=./temp"
info_msg "find ./ -maxdepth 4 -mmin $(( $(stat -c '%Y' $COPY_REMOTE_FILE) - $(date '+%s') )) -type f"
if [ ! -e "$COPY_REMOTE_FILE" ];then
    # 压缩脚本及相关文件
    info_msg "压缩脚本及相关文件到：$COPY_REMOTE_FILE"
    info_msg "压缩文件目录总大小："$(du -ab --max-depth=1 $EXCLUDE_OPTIONS ./|awk 'BEGIN{count=0}{count+=$1}END{if(count < 1024){printf "%0.2fB",count}else if(count < 1048576){printf "%0.2fK",count/1024}else if(count < 1073741824){printf "%0.2fM",count/1048576}else{printf "%0.2fG",count/1073741824}}')
    tar -czf $COPY_REMOTE_FILE $EXCLUDE_OPTIONS ./
    if_error "压缩文件失败，请确认权限和磁盘空间"
fi
# 本地安装方式处理
tag_msg "本地"
case "$ARGV_local_install" in
    async)
        start_install
    ;;
    skip)
        if [ -z "$ARGV_check_install" ] && has_run_shell ".+-install"; then
            error_exit "检测到本地已经有安装脚本运行中"
        fi
        info_msg '跳过本机批量处理'
    ;;
esac
# 循环远程配置数据并执行安装
each_conf start_ssh_install remote
