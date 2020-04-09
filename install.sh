#!/bin/bash
#
# 批量安装服务
# 受 install.conf 配置文件影响
# 

if [ -n "$1" ];then
    CONFIG_FILE=$1;
else
    CONFIG_FILE="install.conf";
fi
if [[ "$0" =~ '/' ]]; then
    cd "`echo "$0" | grep -oP '(/?[^/]+/)+'`"
fi
if [ ! -e "$CONFIG_FILE" ];then
    echo "$CONFIG_FILE config file is not exists"
    exit 1
fi
# 安装服务包
install_server(){
    if [ ! -e "./$1-install.sh" ];then
        echo "$1-install.sh is not exists"
        exit 1;
    fi
    INSTALL_STATUS=`ps aux|grep 'install.sh'`
    if [ -n "`echo $INSTALL_STATUS|grep "$1-install.sh"`" ];then
        echo "$1 already in the installation"
        return 1;
    fi
	PARAMS_LIST=`echo $*|sed "/^/s/$1//"`
    echo "install $1"
    echo "bash ./$1-install.sh $PARAMS_LIST 2>&1"
    {
        if bash ./$1-install.sh $PARAMS_LIST 2>&1 > $1-install.log >/dev/null; then
            echo "install $1 success"
        else
            echo "install $1 fail"
        fi 
    }&
}
# 读取配置
read_config(){
    cat $CONFIG_FILE | grep "\[$1\]" -A $CONFIG_FILE_LINE -m 1 | sed -n '2,$p' | while read LINE
    do
        # 下一个配置块就退出
        if [ -n "`echo $LINE|grep -P "^\[[\w-]+\].*"`" ]; then
            break;
        fi
        # 注释或空行就进入下一次循环
        if [ -n "$(echo $LINE|grep -P "^#.*$")" ] || [ -n "$(echo $LINE|grep -P "^[\t\n\s\r]*$")" ] || [ -z "$LINE" ]; then
            continue;
        fi
        $2 $LINE
    done
}
# 获取文件长度
CONFIG_FILE_LINE=`wc -l $CONFIG_FILE|grep -P '\d+' -o`
if [ -z "$CURRENT_PATH" ];then
    read_config install install_server
fi

