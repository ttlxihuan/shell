#!/bin/bash
############################################################################
# 此脚本用来快速创建git版本库，并携带开启自动更新钩子脚本（用来自动更新到测试环境）
# 仅用于git原生版本库管理，对于使用gitlab或gitolite之类的附属工具就不需要使用此脚本
# 特别说明：脚本只限于ssh协议版本库创建，所以需要引用在 home 目录中
#           脚本会自动提取当前用户并在对应的 home 中创建对应的版本库和证书配置文件
#
# 推荐使用方式：（独立运行脚本）
# bash git-init.sh name
############################################################################

# git版本库所属用户
GIT_USER=git
# git版本库自动同步根目录
GIT_SYNC_PATH=/www/testing

# 输出帮助信息
show_help(){
    echo "
git版本库创建并初始化

命令：
    $(basename "${BASH_SOURCE[0]}") name [-u user] [-s path] [-h|-?]

参数：
    name                初始化创建的版本库名

选项：
    -u user             版本库所属用户，默认：$GIT_USER
    -s path             自动推送过来后自动同步根目录，默认：$GIT_SYNC_PATH
                        实际同步目录： path/name
                        为空即不生成同步钩子脚本
    -h, -?              显示帮助信息

说明：
    此脚本用来快速创建并初始化git版本库，在指定用户home目录中创建git版本库
    脚本仅支持ssh协议处理，并且脚本会自动配置好ssh相关文件及权限信息
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

# 参数处理
if [ $# = 0 ];then
    show_help
fi
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        -u)
            GIT_USER=${@:((++INDEX)):1}
        ;;
        -s)
            GIT_SYNC_PATH=${@:((++INDEX)):1}
        ;;
        *)
            GIT_NAME=${@:$INDEX:1}
        ;;
    esac
done

if [ -n "$GIT_NAME" ];then
    show_error "请指定要创建的版本库名"
fi

if ! which git >/dev/null 2>/dev/null;then
    show_error "没有找到git命令，请确认安装或配置PATH"
fi

# 用户处理
if id "$1" >/dev/null 2>/dev/null;then
    useradd -m -U -s /bin/sh "$GIT_USER"
    if_error "用户创建失败：$GIT_USER"
fi

# home目录处理
if [ "$GIT_USER" = 'root' ];then
    GIT_HOME='/root'
else
    GIT_HOME="/home/$GIT_USER"
fi
if [ ! -d "$GIT_HOME" ];then
    mkdir -p "$GIT_HOME"
fi
chown "$GIT_USER":"$GIT_USER" "$GIT_HOME"

# ssh配置处理
if [ ! -d "$GIT_HOME/.ssh" ];then
    sudo -u "$GIT_USER" mkdir -p "$GIT_HOME/.ssh"
    if_error "ssh目录创建失败：$GIT_HOME/.ssh"
else
    chown -R "$GIT_USER":"$GIT_USER" "$GIT_HOME/.ssh"
fi
chmod 0700 "$GIT_HOME/.ssh"
if [ ! -e "$GIT_HOME/.ssh/authorized_keys" ];then
    sudo -u "$GIT_USER" touch "$GIT_HOME/.ssh/authorized_keys"
else
    chown "$GIT_USER":"$GIT_USER" "$GIT_HOME/.ssh/authorized_keys"
fi
chmod 0600 "$GIT_HOME/.ssh/authorized_keys"
if_error "证书配置文件处理失败：$GIT_HOME/.ssh/authorized_keys"
echo "[info] 证书配置文件正常：$GIT_HOME/.ssh/authorized_keys"

# 确认ssh是否开放证书登录
if [ -e /etc/ssh/sshd_config ];then
    if grep -qP '^\s*RSAAuthentication\s+yes' /etc/ssh/sshd_config &&
     grep -qP '^\s*PubkeyAuthentication\s+yes' /etc/ssh/sshd_config &&
     grep -qP '^\s*AuthorizedKeysFile\s+.ssh/authorized_keys' /etc/ssh/sshd_config;then
        echo '[info] 已开放证书登录'
    else
        echo '[info] 证书登录未开放，请确认以下配置项是否启用：
    RSAAuthentication yes
    PubkeyAuthentication yes
    AuthorizedKeysFile .ssh/authorized_keys'
        while read -p '[read] 证书登录未开放，需要开放吗？ 请输入 [Y/N, y/n]: ' -r INPUT_RESULT; do 
            if [[ "$INPUT_RESULT" =~ ^(Y|y)$ ]];then
                if grep -qP '^(\s*#+\s*)?(RSAAuthentication)\s+.*' /etc/ssh/sshd_config;then
                    sed -i -r 's/^(\s*#+\s*)?(RSAAuthentication)\s+.*/\2 yes/' /etc/ssh/sshd_config
                else
                    echo 'RSAAuthentication yes' >> /etc/ssh/sshd_config
                fi
                if grep -qP '^(\s*#+\s*)?(PubkeyAuthentication)\s+.*' /etc/ssh/sshd_config;then
                    sed -i -r 's/^(\s*#+\s*)?(PubkeyAuthentication)\s+.*/\2 yes/' /etc/ssh/sshd_config
                else
                    echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
                fi
                if grep -qP '^(\s*#+\s*)?(AuthorizedKeysFile)\s+.*' /etc/ssh/sshd_config;then
                    sed -i -r 's/^(\s*#+\s*)?(AuthorizedKeysFile)\s+.*/\2 .ssh\/authorized_keys/' /etc/ssh/sshd_config
                else
                    echo 'AuthorizedKeysFile yes' >> /etc/ssh/sshd_config
                fi
                # 重启ssh服务
                if which systemctl;then
                    systemctl restart sshd
                elif which service;then
                    service sshd restart
                else
                    echo '[warn] 请手动重启sshd服务！'
                fi
                break
            elif [[ "$INPUT_RESULT" =~ ^(N|n)$ ]];then
                echo '[warn] 已放弃启动证书登录！'
            else
                echo '[warn] 输入错误，请重新输入！'
            fi
        done
    fi
else
    echo '[warn] sshd配置文件 /etc/ssh/sshd_config 不存在，跳过确认证书登录'
fi

echo "[info] 创建版本库：$GIT_NAME"
cd "$GIT_HOME"
sudo -u "$GIT_USER" git init "$GIT_NAME" --bare
if_error "版本库创建失败：$GIT_NAME"

# 修改钩子自动同步脚本
if [ -n "$GIT_SYNC_PATH" ];then
    cd "$GIT_NAME/hooks/"
    cp post-update.sample post-update
    chmod +x post-update

    cat >> post-update <<EOF

echo '+++++++++++++++++++++++++++++++++++++++++';
echo "[hook] 同步代码";

cd $GIT_SYNC_PATH/$(pwd|grep -oP /[^/]+$);

git reset --hard HEAD

git pull

if [ \$? = '0' ]; then
    echo '[success] 同步成功';
else
    echo '[fail] 同步失败';
fi
echo '+++++++++++++++++++++++++++++++++++++++++';

EOF
    # 创建好对应的目录
    if [ ! -d "$GIT_SYNC_PATH" ];then
        sudo -u "$GIT_USER" mkdir -p "$GIT_SYNC_PATH"
    else
        chown -R "$GIT_USER":"$GIT_USER" "$GIT_SYNC_PATH"
    fi
    git clone "$GIT_HOME/$GIT_NAME"
fi

# 获取ssh端口号
SSH_PORTS=$(netstat -ntlp|grep sshd|awk '{print $4}'|grep -oP '\d+$')
# 获取地址
LOCAL_IPS=$(ifconfig|grep -P 'inet \d+(\.\d+)+' -o|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o)
# 获取外网IP地址
PUBLIC_IP=$(curl cip.cc 2>/dev/null|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o|head -n 1)

# 展示可用版本库地址
echo '[info] 内网库地址：'
while read -r SSH_PORT;do
    while read -r LOCAL_IP;do
        echo " ssh://$GIT_USER@$LOCAL_IP:$SSH_PORT/$GIT_SYNC_PATH/$GIT_NAME"
    done <<EOF
$LOCAL_IPS
EOF
done <<EOF
$SSH_PORTS
EOF

echo '[info] 公网库地址：'
while read -r SSH_PORT;do
    echo "ssh://$GIT_USER@$PUBLIC_IP:$SSH_PORT/$GIT_SYNC_PATH/$GIT_NAME"
done <<EOF
$SSH_PORTS
EOF

echo '[info] 注意防火墙是否有限制指定的端口号'