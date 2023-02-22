#!/bin/bash
############################################################################
# 此脚本用来快速创建svn版本库，并携带开启自动更新钩子脚本（用来自动更新到测试环境）
# 脚本可用方便管理账号和配置账号及版本库管理，功能主要以常用为准
# 特别说明：svn版本库是运行在svnadmin监听服务下，需要指定svnadmin工作目录
#           不指定监听工作目录将以当前目录为准，暂不对监听命令中指定的目录（监听可能存在多个）
#
# 推荐使用方式：（独立运行脚本）
# bash svn-init.sh name
############################################################################

# svn版本库自动同步根目录
SVN_SYNC_PATH=/www/testing
SVN_SYNC_USER=auto-sync
SVN_SYNC_ROLE=develop
# 输出帮助信息
show_help(){
    echo "
svn版本库创建配置工具

命令：
    $(basename "${BASH_SOURCE[0]}") name [-s path] [--sync-user user] [-h|-?]

参数：
    name                初始化创建的版本库名
    
选项：
    -w path             svn服务工作目录，不指定为当前目录
    -s path             自动推送过来后自动同步根目录，默认：$SVN_SYNC_PATH
                        实际同步目录： path/name
                        为空即不生成同步钩子脚本
    -p role             指定版本库角色名，用来区分不同的授权配置文件（为空即不区分）
                        同一角色名共用一个授权文件，方便多库统一管理（密码配置全局共用）
                        比如使用：php、h5、java、front、backend 等
                        角色名默认为：$SVN_SYNC_ROLE
    --sync-user user    自动同步用户，默认 $SVN_SYNC_USER
                        密码会自动提取配置文件
                        用户和密码如果没有则自动创建
                        同步目录为空此选项无效
    -h, -?              显示帮助信息

说明：
    此脚本用来快速创建并初始化svn版本库，在指定工作目录中创建svn版本库
    脚本会自动配置好svn相关文件及权限信息，注意工作目录所属用户，版本库创建以所属用户进行
    用户配置会在工作目录上创建一个svn-conf目录用户存放用户名和密码，方便统一配置
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1" >&2
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
SVN_PATH=$(pwd)
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        -w)
            SVN_PATH=${@:((++INDEX)):1}
        ;;
        -s)
            SVN_SYNC_PATH=${@:((++INDEX)):1}
            if [ ! -d "$SVN_SYNC_PATH" ];then
                show_error "工作目录不存在：$SVN_SYNC_PATH"
            fi
        ;;
        --sync-user)
            SVN_SYNC_USER=${@:((++INDEX)):1}
        ;;
        *)
            SVN_NAME=${@:$INDEX:1}
        ;;
    esac
done

# 版本库名判断
if [ -z "$SVN_NAME" ];then
    show_error "请指定要创建的版本库名"
elif ! [[ "$SVN_NAME" =~ ^[a-zA-Z0-9_\-\.]+$ ]];then
    echo "版本库名：$SVN_NAME ，包含（字母、数字、-_.）以外的字符，可能会导致使用异常，确认创建该版本库吗？"
    if read -p '[read] 输入 [Y/y] 确认，其它任何字符退出: ' -r INPUT_RESULT && [ "$INPUT_RESULT" != 'y' -a "$INPUT_RESULT" != 'Y' ];then
        show_error "终止创建版本库"
    fi
fi

SVNADMIN_COMMAND=$(which svnadmin 2>/dev/null)
if [ $? != 0 ];then
    show_error "没有找到svnadmin命令，请确认安装或配置PATH"
fi

# 需要同步就必需有svn命令
if [ -n "$SVN_SYNC_PATH" ];then
    SVN_COMMAND=$(which svn 2>/dev/null)
    if [ $? != 0 ];then
        show_error "没有找到svn命令，请确认安装或配置PATH"
    fi
fi

if [ -n "$SVN_SYNC_PATH" ] && [ -z "$SVN_SYNC_USER" ];then
    show_error "请指定同步用户"
fi

echo "[info] 创建版本库：$SVN_NAME"
cd "$SVN_PATH"

# 获取工作目录用户名
SVN_USER=$(stat -c '%U' ./)

# 获取svn监听端口号
SVN_PORTS=$(netstat -ntlp|grep svnserve|awk '{print $4}'|grep -oP '\d+$'|sort|uniq)
if [ -z "$SVN_PORTS" ];then
    SVNSERVE_COMMAND=$(which svnserve 2>/dev/null)
    if [ $? = 0 ];then
        show_error "没有找到svnserve监听进程，可以试着运行： sudo -u $SVN_USER $SVNSERVE_COMMAND -d -r $SVN_PATH"
    else
        show_error "没有找到svnserve监听进程，也没有找到svnserve命令，请确认安装或配置PATH"
    fi
fi

sudo -u "$SVN_USER" $SVNADMIN_COMMAND create "$SVN_NAME"
if_error "版本库创建失败：$SVN_NAME"

# 配置文件处理
if [ ! -d ./svn-conf ];then
    sudo -u "$SVN_USER" mkdir ./svn-conf
fi

SVN_CONF_PASSWD=$SVN_PATH/svn-conf/passwd
SVN_CONF_AUTHZ=$SVN_PATH/svn-conf/authz

# 配置文件处理
edit_conf(){
    local CONF_KEY SVN_CONF_NUM GREP_REG=${2//[/\\[}
    GREP_REG=${GREP_REG//]/\\]}
    SVN_CONF_NUM=$(grep -n "^${GREP_REG}" $1|grep -oP '^\d+')
    if [ -z "$SVN_CONF_NUM" ];then
        echo -e "\n$2" >> $1
        SVN_CONF_NUM=$(grep -n "^$GREP_REG" $1|grep -oP '^\d+')
    fi
    for ((CONF_KEY=3; CONF_KEY<=$#; CONF_KEY++));do
        sed -i "${SVN_CONF_NUM}a${@:$CONF_KEY:1}" $1
    done
}

if [ -n "$SVN_SYNC_ROLE" ];then
    SVN_CONF_AUTHZ=$SVN_CONF_AUTHZ-$SVN_SYNC_ROLE
fi
if [ ! -e $SVN_CONF_PASSWD ];then
    cp ./$SVN_NAME/conf/passwd $SVN_CONF_PASSWD
fi
if [ ! -e $SVN_CONF_AUTHZ ];then
    cp ./$SVN_NAME/conf/authz $SVN_CONF_AUTHZ
    edit_conf "$SVN_CONF_AUTHZ" '[/]' '@visitor=r' '@develop=rw' '@admin=rw'
    edit_conf "$SVN_CONF_AUTHZ" '[groups]' 'visitor=' 'develop=' 'admin='
fi
chown -R "$SVN_USER":"$SVN_USER" ./svn-conf
# 用户配置
sed -i -r "s,^(\s*#+\s*)?(password-db\s*=).*,\2 $SVN_CONF_PASSWD," "./$SVN_NAME/conf/svnserve.conf"
sed -i -r "s,^(\s*#+\s*)?(authz-db\s*=).*,\2 $SVN_CONF_AUTHZ," "./$SVN_NAME/conf/svnserve.conf"
# 访问权限配置
sed -i -r 's/^(\s*#+\s*)?(anon-access\s*=).*/\2 none/' "./$SVN_NAME/conf/svnserve.conf"
sed -i -r 's/^(\s*#+\s*)?(auth-access\s*=).*/\2 write/' "./$SVN_NAME/conf/svnserve.conf"

# 修改钩子自动同步脚本
if [ -n "$SVN_SYNC_PATH" ];then
    echo "[info] 同步代码目录：$SVN_SYNC_PATH"
    # 同步用户名处理
    if ! grep -q "^@visitor\s*=.*" $SVN_CONF_AUTHZ;then
        # 创建用户
        edit_conf "$SVN_CONF_AUTHZ" '[/]' '@visitor=r'
    fi
    if ! grep -qP "^visitor\s*=(.*,)?(\s*$SVN_SYNC_USER\s*)(,.*)?$" $SVN_CONF_AUTHZ;then
        # 创建用户
        SVN_CONF_NUM=$(grep -n "^visitor\s*=" $SVN_CONF_AUTHZ|grep -oP '^\d+')
        if [ -n "$SVN_CONF_NUM" ];then
            JOIN_USER=','
            if grep -q "^visitor\s*=\s*$" $SVN_CONF_AUTHZ;then
                JOIN_USER=''
            fi
            sed -i "${SVN_CONF_NUM}s/$/&$JOIN_USER$SVN_SYNC_USER/" $SVN_CONF_AUTHZ
        else
            edit_conf "$SVN_CONF_AUTHZ" '[groups]' "visitor=$SVN_SYNC_USER"
        fi
    fi
    # 获取同步密码
    SVN_SYNC_PASSWD=$(grep "^$SVN_SYNC_USER=.*" $SVN_CONF_PASSWD)
    SVN_SYNC_PASSWD=${SVN_SYNC_PASSWD#*=}
    if [ -z "$SVN_SYNC_PASSWD" ];then
        # 创建密码
        SVN_SYNC_PASSWD=$(ifconfig -a 2>&1|md5sum -t|awk '{print $1}')
        echo "$SVN_SYNC_USER=$SVN_SYNC_PASSWD" >> $SVN_CONF_PASSWD
    fi
    cd "$SVN_NAME/hooks/"
    sudo -u "$SVN_USER" cp post-commit.tmpl post-commit
    chmod +x post-commit
    sed -i -r 's/^(\s*\w+)/#\1/' post-commit
    cat >> post-commit <<EOF

export LANG="en_US.UTF-8"
cd $SVN_SYNC_PATH/$SVN_NAME;
$SVN_COMMAND revert -R ./
$SVN_COMMAND update --username=$SVN_SYNC_USER --password=$SVN_SYNC_PASSWD --no-auth-cache

EOF
    # 创建好对应的目录
    if [ ! -d "$SVN_SYNC_PATH" ];then
        mkdir -p "$SVN_SYNC_PATH"
    fi
    cd "$SVN_SYNC_PATH"
    $SVN_COMMAND checkout "svn://127.0.0.1:$(echo $SVN_PORTS|head -n 1)/$SVN_NAME" --username=$SVN_SYNC_USER --password=$SVN_SYNC_PASSWD
    # 修改所属用户
    chown -R "$SVN_USER":"$SVN_USER" "$SVN_SYNC_PATH/$SVN_NAME"
fi

# 获取地址
LOCAL_IPS=$(ifconfig|grep -P 'inet (addr:)?\d+(\.\d+)+' -o|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o|sort|uniq)
# 获取外网IP地址
PUBLIC_IP=$(curl cip.cc 2>/dev/null|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o|head -n 1)

echo '[info] 注意防火墙是否有限制指定的端口号'
# 展示可用版本库地址
echo '[info] 内网库地址：'
while read -r SVN_PORT;do
    while read -r LOCAL_IP;do
        if [ -n "$LOCAL_IP" ];then
            echo "  svn://$LOCAL_IP:$SVN_PORT/$SVN_NAME"
        fi
    done <<EOF
$LOCAL_IPS
EOF
done <<EOF
$SVN_PORTS
EOF

echo '[info] 公网库地址：'
    if [ -n "$PUBLIC_IP" ];then
    while read -r SVN_PORT;do
        echo "  svn://$PUBLIC_IP:$SVN_PORT/$SVN_NAME"
    done <<EOF
$SVN_PORTS
EOF
fi
