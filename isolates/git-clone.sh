#!/bin/bash
############################################################################
# 此脚本用来快速克隆git版本库代码，并且尽可能使用证书模式，当证书不存在时默认自动创建证书
# 同时能修复部分证书登录失败问题，对于github上会进行多证书创建，对于其它版本库则使用同一证书
# 如果已经存在证书并且登录失败，则可以进行修复
#   1、本地.ssh目录对应的权限是否正常
#   2、判断ssh是否开启了对应的证书类型
#   3、判断服务器是配置是否到位，此步可能需要密码登录
#
# 此脚可在window系统下可以使用git-bash工具运行（可将此文件放到GIT安装目录下: usr/bin/）
#
# 推荐使用方式：（独立运行脚本）
# bash git-clone.sh ssh://host/path
############################################################################

############################################################################
# git 使用异常错误收集
############################################################################
# 1、git clone 报错：fatal: unable to checkout working tree
#   在window系统中文件名长度或包含特殊字符超出限制，一般是指版本库里的文件存在不兼容window系统的文件名
#   在报错上面找到 error: 信息段，一般是指定异常文件，需要进行修改
# 2、git 连接远程服务器时无法使用证书，每次都自动切换到密码模式
#   核对下本地/etc/ssh/ssh_config是否有对应配置，包括开放域名和证书类型
# 3、如果ssh证书连接失败，可以查看服务器的日志 /var/log/messages 进行排除
#
############################################################################

# 输出帮助信息
show_help(){
    echo "
git代码克隆脚本

命令：
    $(basename "${BASH_SOURCE[0]}") git-addr [-t type] [-i identity_file] [-s] [-h|-?]
    
参数：
    git-addr            版本库地址，仅限使用ssh协议版本库地址
    
选项：
    -t type             指定证书类型，默认rsa
                        支持：$KEY_TYPE_RULES
    -i identity_file    指定登录证书私钥，不指定将使用默认证书
                        默认证书会按不同的情况进行区分的
    -s                  要求克隆使用独立证书，默认尽可能共用证书
                        github会自动改为独立证书
    -h, -?              显示帮助信息

说明：
    此脚本用来快速克隆git版本库代码，并且尽可能使用证书模式，当证书不存在时默认自动创建证书
    如果之前已经操作过证书并无法正常克隆代码时会尝试进行修复，尽可能保证克隆成功
    sshd需要开启证书登录配置（注意证书类型），兼容github版本库克隆
    自配版本库服务器最好能确认证书是否能登录，并确定使用证书类型，比如：rsa、dsa
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1"
    exit 1
}
if_error(){
    if [ $? != 0 ];then
        show_error "$1"
    fi
}
# 默认不独享证书
KEY_TYPE=rsa
CERTIFICATE_ALONE=0
KEY_TYPE_RULES=$(ssh-keygen --help 2>&1|grep \\-t|sed -r 's/\s*\|\s*/|/g'|grep -oP '\S+(\|[^\s\]]+)')
if [ -z "$KEY_TYPE_RULES" ];then
    KEY_TYPE_RULES='dsa|rsa'
fi
# 参数处理
if [ $# = 0 ];then
    show_help
fi
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        -i)
            IDENTITY_FILE=${@:((++INDEX)):1}
        ;;
        -t)
            KEY_TYPE=${@:((++INDEX)):1}
            if ! [[ "$KEY_TYPE" =~ ^($KEY_TYPE_RULES)$ ]];then
                show_error "未知证书类型：$KEY_TYPE"
            fi
        ;;
        -s)
            CERTIFICATE_ALONE=1
        ;;
        *)
            GIT_ADDR=${@:$INDEX:1}
            if ! [[ "$GIT_ADDR" =~ ^(ssh://)?[^@]+@[^/:]+:[^/]+(/[^/]+)+$ ]];then
                show_error "暂不支持版本库地址：$GIT_ADDR"
            fi
            # 提取版本库地址域名
            GIT_HOST=$(echo "$GIT_ADDR"|grep -oP '^(ssh://)?[^@]+@[^/:]+'|sed -r 's,^(ssh://)?[^@]+@,,')
        ;;
    esac
done

# 版本库地址处理
if [ -z "$GIT_ADDR" ];then
    show_error "请指定要克隆的版本库地址"
fi
# 判断github
if [[ "$GIT_ADDR" =~ ^git@github\.com:.+/.+\.git$ ]];then
    CERTIFICATE_ALONE=1
fi

# 证书处理
GIT_AS=$(echo "$GIT_ADDR"|grep -oP '[^/]+(\.git)?$'|sed -r 's/\.git$//')
if [ -z "$GIT_AS" ];then
    show_error "暂时不支持此版本库地址：$GIT_ADDR"
fi
if [ -z "$IDENTITY_FILE" ];then
    # 独享证书处理
    if [ "$CERTIFICATE_ALONE" = 1 ];then
        IDENTITY_FILE=~/.ssh/${GIT_AS}_id_$KEY_TYPE
    else
        IDENTITY_FILE=~/.ssh/id_$KEY_TYPE
    fi
fi
if [ ! -e $IDENTITY_FILE ];then
    echo "[info] 创建证书：$IDENTITY_FILE"
    ssh-keygen -t $KEY_TYPE -f $IDENTITY_FILE
    if_error "证书创建失败"
fi
ssh-keygen -B -f $IDENTITY_FILE  >/dev/null 2>&1
if_error "不是有效证书文件：$IDENTITY_FILE"

# 本地证书及目录权限处理
#if uname|grep -qP 'MINGW(64|32)';then
#    chmod 0755 $(dirname $IDENTITY_FILE)
#    chmod 0644 $IDENTITY_FILE
#    chmod 0644 $IDENTITY_FILE.pub
#else
#    chmod 0700 $(dirname $IDENTITY_FILE)
#    chmod 0600 $IDENTITY_FILE
#    chmod 0644 $IDENTITY_FILE.pub
#fi

# 配置独享证书处理
if [ "$CERTIFICATE_ALONE" = 1 ];then
    echo "[info] 配置git版本库地址别名，指定专用证书"
    LINE_NUM=0
    # 判断ssh是否配置域名
    HAS_HOST=0
    while read -r LINE;do
        ((LINE_NUM++))
        if [[ "$LINE" =~ ^[[:space:]]*(#.*)?$ ]];then
            continue
        fi
        if [[ "$LINE" =~ ^[[:space:]]*Host[[:space:]]+.*$ ]];then
            IS_CURRENT_POS=$(echo "$LINE"|sed -r 's/^\s*Host\s+//')
        elif [ "$IS_CURRENT_POS" = "${GIT_HOST}-${GIT_AS}" ] && 
            [[ "$LINE" =~ ^[[:space:]]*(IdentityFile)[[:space:]]+ ]];then
            # 配置内容不符合就修改
            if ! echo "$LINE"|grep -q "$IDENTITY_FILE";then
                echo "${LINE_NUM}s,$,\,$IDENTITY_FILE,"
                sed -i "${LINE_NUM}s,$,\,$IDENTITY_FILE," ~/.ssh/config
            fi
            HAS_HOST=1
        fi
    done < ~/.ssh/config
    # 没有配置块就添加
    if [ "$HAS_HOST" = 0 ];then
        cat >> ~/.ssh/config <<EOF

Host ${GIT_HOST}-${GIT_AS}
    Hostname ${GIT_HOST}
    IdentityFile $IDENTITY_FILE
EOF
    fi
    # 修改git版本库地址
    GIT_ADDR=$(echo "$GIT_ADDR"|sed "s/@$GIT_HOST:/@${GIT_HOST}-${GIT_AS}:/")
fi

# 配置ssh允许证书类型
SSH_KEY_NAME=$(grep -oP '^\S+' ${IDENTITY_FILE}.pub)
if [ -n "$SSH_KEY_NAME" ];then
    echo "[info] 配置证书类型许可"
    LINE_NUM=0
    # 判断ssh是否开放了对应的证书类型
    HAS_KEY_TYPE=0
    while read -r LINE;do
        ((LINE_NUM++))
        if [[ "$LINE" =~ ^[[:space:]]*(#.*)?$ ]];then
            continue
        fi
        if [[ "$LINE" =~ ^[[:space:]]*Host[[:space:]]+.*$ ]];then
            IS_CURRENT_POS=$(echo "$LINE"|sed -r 's/^\s*Host\s+//')
        elif [ "$IS_CURRENT_POS" = '*' -o "$IS_CURRENT_POS" = "${GIT_HOST}" ] && 
            [[ "$LINE" =~ ^[[:space:]]*(HostkeyAlgorithms|PubkeyAcceptedAlgorithms)[[:space:]]+ ]];then
            # 配置内容不符合就增加
            if ! echo "$LINE"|grep -qP "(\+|,)$SSH_KEY_NAME(\s+|$|,)";then
                sed -i "${LINE_NUM}s/$/&,$SSH_KEY_NAME/" /etc/ssh/ssh_config
            fi
            HAS_KEY_TYPE=1
        fi
    done < /etc/ssh/ssh_config
    # 没有配置块就添加
    if [ "$HAS_KEY_TYPE" = 0 ];then
        # 追加开放
        cat >> /etc/ssh/ssh_config <<EOF
Host *
    HostkeyAlgorithms +$SSH_KEY_NAME
    PubkeyAcceptedAlgorithms +$SSH_KEY_NAME
EOF
    fi
fi

SSH_ADDR=$(echo "$GIT_ADDR"|grep -oP '^(ssh://)?[^@]+@[^/:]+:[^/]+'|sed -r 's,^(ssh://)?,,')
SSH_HOST=${SSH_ADDR%:*}
SSH_PORT=${SSH_ADDR##*:}
SSH_USER=${SSH_ADDR%%@*}
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || (( SSH_PORT < 0 || SSH_PORT > 65535 ));then
    SSH_PORT=22
fi
if [ "$SSH_USER" = 'root' ];then
    SSH_HOME='/root'
else
    SSH_HOME="/home/$SSH_USER"
fi

# 验证证书是否可连接
while true;do
    echo -n "[info] 验证证书是否可连接"
    SSH_LOGIN_INFO=$(ssh -Tnv $SSH_HOST -p $SSH_PORT -i $IDENTITY_FILE -o PasswordAuthentication=no -o StrictHostKeyChecking=no 2>&1)
    if [ $? = 0 -o $? = 128 ] || echo "$SSH_LOGIN_INFO"|grep -q 'successfully authenticated';then
        echo ' YES'
        break
    fi
    echo ' NO'
    echo "[info] 证书无法连接，请在${GIT_HOST}上配置证书权限"
    if [ "${GIT_HOST}" != 'github.com' ];then
        echo " 服务器证书配置及验证处理流程：
    一、gitlab界面类配置
        1、打开界面管理进入密钥配置
        2、复制本地公钥证书文本 $IDENTITY_FILE.pub
        3、保存证书
    二、git命令类配置
        1、ssh连接服务器（能登录操作账号即可）
        2、复制本地公钥证书文本 $IDENTITY_FILE.pub
        3、追加到服务器配置文件 ${SSH_HOME}/.ssh/authorized_keys
        4、权限处理 chmod 0700 ${SSH_HOME}/.ssh/ && chmod 0600 ${SSH_HOME}/.ssh/authorized_keys
        5、确认sshd服务是否开启证书登录，配置文件 /etc/ssh/sshd_config
            RSAAuthentication yes
            PubkeyAuthentication yes
            AuthorizedKeysFile .ssh/authorized_keys
           配置完后重启sshd服务
    三、gitolite命令类配置
        1、给版本库 $GIT_HOST:gitolite-admin 增加证书
        2、复制本地公钥证书文件 $IDENTITY_FILE.pub 注意修改个文件名
        3、粘贴到库中 keydir 目录中
        4、配置库中 conf/gitolite.conf 文件开放权限
        5、提交并推送到远程服务器

 配置完后可通过ssh验证证书是否成功：
    ssh -Tnv $SSH_HOST -p $SSH_PORT -i $IDENTITY_FILE -o PasswordAuthentication=no -o StrictHostKeyChecking=no
    
    提示权限成功即可，界面类可能会提示 does not provide shell access.
"
    fi
    if uname|grep -qP 'MINGW(64|32)';then
        echo "[info] 即将打开证书，请复制公钥：$IDENTITY_FILE.pub"
        sleep 2
        start $IDENTITY_FILE.pub
        if [ "${GIT_HOST}" = 'github.com' ];then
            echo "[info] 即将打开github密钥配置页面，请将公钥粘贴上进行密钥访问配置"
            sleep 2
            start https://github.com/${SSH_ADDR##*:}/${GIT_AS}/settings/keys/new
        fi
    elif [ "${GIT_HOST}" = 'github.com' ];then
        echo "[info] 1、打开： https://github.com/${SSH_ADDR##*:}/${GIT_AS}/settings/keys/new"
        echo "[info] 2、打开并复制公钥：$IDENTITY_FILE.pub 配置到github并保存"
    fi
    while read -p '[read] 请确认证书已经配置好，请输入 [Y/N, y/n]: ' -r INPUT_RESULT; do 
        if [[ "$INPUT_RESULT" =~ ^(Y|y)$ ]];then
            break
        elif [[ "$INPUT_RESULT" =~ ^(N|n)$ ]];then
            show_error '已放弃克隆仓库！'
        else
            echo '[warn] 输入错误，请重新输入！'
        fi
    done
done

# 克隆仓库
echo "[info] 克隆仓库：$GIT_ADDR"
git clone $GIT_ADDR --config http.sslCert=$IDENTITY_FILE
if [ $? = 0 ];then
    echo '[info] git克隆成功'
else
    echo '[warn] git克隆失败'
fi
