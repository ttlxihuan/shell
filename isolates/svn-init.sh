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
# 输出帮助信息
show_help(){
    echo "
svn版本库创建并初始化

命令：
    $(basename "${BASH_SOURCE[0]}") name [-s path] [--sync-user user] [-h|-?]

参数：
    name                初始化创建的版本库名
    
选项：
    -w path             svn服务工作目录，不指定为当前目录
    -s path             自动推送过来后自动同步根目录，默认：$SVN_SYNC_PATH
                        实际同步目录： path/name
                        为空即不生成同步钩子脚本
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
SVN_PATH=$(pwd)
for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        -h|-\?)
            show_help
        ;;
        -p)
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

if [ -n "$SVN_NAME" ];then
    show_error "请指定要创建的版本库名"
fi

if ! which svnadmin >/dev/null 2>/dev/null;then
    show_error "没有找到svnadmin命令，请确认安装或配置PATH"
fi

if [ -n "$SVN_SYNC_PATH" ] && [-z "$SVN_SYNC_USER"];then
    show_error "请指定同步用户"
fi

echo "[info] 创建版本库：$SVN_NAME"
cd "$SVN_PATH"

# 获取工作目录用户名
SVN_USER=(stat -c '%U' ./)

sudo -u "$SVN_USER" svnadmin create "$SVN_NAME"
if_error "版本库创建失败：$SVN_NAME"

# 配置文件处理
if [ ! -d ./svn-conf ];then
    sudo -u "$SVN_USER" mkdir ./svn-conf
fi
if [ ! -e ./svn-conf/passwd ];then
    cp ./$SVN_NAME/conf/passwd ./svn-conf/passwd
fi
if [ ! -e ./svn-conf/authz ];then
    cp ./$SVN_NAME/conf/authz ./svn-conf/authz
fi
chown -R "$SVN_USER":"$SVN_USER" ./svn-conf
# 用户配置
sed -i -r "s,^(\s*#+\s*)?(password-db\s*=).*,\2 $SVN_PATH/svn-conf/passwd," "./$SVN_NAME/conf/svnserve.conf"
sed -i -r "s,^(\s*#+\s*)?(authz-db\s*=).*,\2 $SVN_PATH/svn-conf/authz," "./$SVN_NAME/conf/svnserve.conf"
# 访问权限配置
sed -i -r 's/^(\s*#+\s*)?(anon-access\s*=).*/\2 none/' "./$SVN_NAME/conf/svnserve.conf"
sed -i -r 's/^(\s*#+\s*)?(auth-access\s*=).*/\2 write/' "./$SVN_NAME/conf/svnserve.conf"

# 修改钩子自动同步脚本
if [ -n "$SVN_SYNC_PATH" ];then
    # 同步用户名处理
    if ! grep -q "^$SVN_SYNC_USER=.*" ./svn-conf/authz;then
        # 创建用户
        LINE_NUM=0
        while read -r LINE;do
            ((LINE_NUM++))
            if [[ "$LINE" =~ ^[[:space:]]*(#.*)?$ ]];then
                continue
            fi
            if [[ "$LINE" = ^[[:space:]]*\[users\][[:space:]]*$ ]];then
                sed -i "${LINE_NUM}a$SVN_SYNC_USER=r" ./svn-conf/authz
                break
            fi
        done < ./svn-conf/authz
    fi

    # 获取同步密码
    SVN_SYNC_PASSWD=$(grep -q "^$SVN_SYNC_USER=.*" ./svn-conf/authz)
    if [ -z "$SVN_SYNC_PASSWD" ];then
        # 创建密码
        SVN_SYNC_PASSWD=$(ifconfig -a 2>&1|md5sum -t|awk '{print $1}')
        echo "$SVN_SYNC_USER=$SVN_SYNC_PASSWD" >> ./svn-conf/authz
    fi

    cd "$SVN_NAME/hooks/"
    cp post-commit.tmpl post-commit
    chmod +x post-commit
    cat >> post-commit <<EOF

echo '+++++++++++++++++++++++++++++++++++++++++';
echo "[hook] 同步代码";

export LANG="en_US.UTF-8"

cd $SVN_SYNC_PATH/$(basename "$1");

svn reset

svn update --username=$SVN_SYNC_USER --password=$SVN_SYNC_PASSWD --no-auth-cache

if [ \$? = '0' ]; then
    echo '[success] 同步成功';
else
    echo '[fail] 同步失败';
fi
echo '+++++++++++++++++++++++++++++++++++++++++';

EOF
    # 创建好对应的目录
    if [ ! -d "$SVN_SYNC_PATH" ];then
        sudo -u "$SVN_NAME" mkdir -p "$SVN_SYNC_PATH"
    else
        chown -R "$SVN_NAME":"$SVN_NAME" "$SVN_SYNC_PATH"
    fi
    cd "$SVN_SYNC_PATH"
    svn checkout "$SVN_PATH/$SVN_NAME"
fi

# 获取ssh端口号
SVN_PORTS=$(netstat -ntlp|grep svnserve|awk '{print $4}'|grep -oP '\d+$')
# 获取地址
LOCAL_IPS=$(ifconfig|grep -P 'inet \d+(\.\d+)+' -o|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o)
# 获取外网IP地址
PUBLIC_IP=$(curl cip.cc 2>/dev/null|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o|head -n 1)

# 展示可用版本库地址
echo '[info] 内网库地址：'
while read -r SVN_PORT;do
    while read -r LOCAL_IP;do
        echo " svn://$LOCAL_IP:$SVN_PORT/$SVN_SYNC_PATH/$SVN_NAME"
    done <<EOF
$LOCAL_IPS
EOF
done <<EOF
$SVN_PORTS
EOF

echo '[info] 公网库地址：'
while read -r SVN_PORT;do
    echo "svn://$PUBLIC_IP:$SVN_PORT/$SVN_SYNC_PATH/$SVN_NAME"
done <<EOF
$SVN_PORTS
EOF

echo '[info] 注意防火墙是否有限制指定的端口号'
