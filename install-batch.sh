#!/bin/bash
#
# 批量安装服务
# 受 install-batch.conf 配置文件影响
if [ -n "$1" ];then
    CONFIG_FILE=$1;
else
    CONFIG_FILE="install-batch.conf";
fi
if [[ "$0" =~ '/' ]]; then
    cd "`echo "$0" | grep -oP '(/?[^/]+/)+'`"
fi
if [ ! -e "$CONFIG_FILE" ];then
    echo "$CONFIG_FILE 配置文件不存在"
    exit 1
fi
# 安装服务包
# @command install_server $name [$options ...]
# @param $name              指定安装服务名，比如：php
# @param $options           指定安装版脚本定制参数集
# return 1|0
install_server(){
    if [ ! -e "./$1-install.sh" ];then
        echo "$1-install.sh 脚本不存在"
        exit 1;
    fi
    local INSTALL_STATUS=`ps aux|grep 'install.sh'`
    if [ -n "`echo $INSTALL_STATUS|grep "$1-install.sh"`" ];then
        echo "$1 脚本已经在安装中"
        return 1;
    fi
    unset INDEX
    if ps aux|grep -P "$1-install\.sh\s+(new|\d+\.\d+)"; then
        echo "$1 已经在安装运行中"
    else
        echo "安装：$1 ，安装信息保存在：$1-install.log"
        echo "nohup bash ./$1-install.sh ${@:2} --data-free=save >> $1-install.log 2>/dev/null &"
        nohup bash ./$1-install.sh ${@:2} --data-free=save >> $1-install.log 2>/dev/null &
    fi
}
# 读取配置文件
# @command read_config $node_name $command_name
# @param $node_name         指定配置节点，配置文件中的[node_name]块内容
# @param $command_name      读取配置后调用的命令
# return 1|0
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
if [ "$0" = 'install-batch.sh' ] || [[ "$0" == */install-batch.sh ]];then
    read_config install install_server
fi

