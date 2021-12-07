#!/bin/bash
#
# 批量安装服务

# 参数信息配置
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    SHELL_RUN_DESCRIPTION='批量安装'
fi
SHELL_RUN_HELP='
批量安装仅限支持的脚本，多个安装并行操作

1、批量安装会强制空间处理（增加安装脚本参数 --data-free=save）。
2、内存空间不足会增加虚拟内存，磁盘空间不够将停止安装，安装前多了解下。
'$SHELL_RUN_HELP
DEFINE_TOOL_PARAMS="$DEFINE_TOOL_PARAMS
[-f, --config=':etc/install-batch.conf'] 指定配置文件
"
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../includes/tool.sh || exit
# 提取配置文件路径
if ! get_file_path $ARGV_config ARGV_config 1;then
    error_exit "--config 未指定有效配置文件：$ARGV_config"
fi
# 安装服务包
# @command install_server $name [$options ...]
# @param $name              指定安装服务名，比如：php
# @param $options           指定安装版脚本定制参数集
# return 1|0
install_server(){
    local INSTALL_FILE_PATH
    find_project_file install "$1" INSTALL_FILE_PATH
    if ps aux|grep -P "$1-install\.sh\s+(new|\d+\.\d+)"; then
        warn_msg "$1 已经在安装运行中"
    else
        info_msg "安装：$1 ，安装信息保存在：$SHELL_WROK_TEMP_PATH/$1-install.log"
        run_msg "nohup bash $INSTALL_FILE_PATH ${@:2} --data-free=save >> $SHELL_WROK_TEMP_PATH/$1-install.log 2>/dev/null &"
        nohup bash $INSTALL_FILE_PATH ${@:2} --data-free=save >> $SHELL_WROK_TEMP_PATH/$1-install.log 2>/dev/null &
    fi
}
# 读取配置文件
# @command read_config $node_name $command_name
# @param $node_name         指定配置节点，配置文件中的[node_name]块内容
# @param $command_name      读取配置后调用的命令
# return 1|0
read_config(){
    cat $ARGV_config | grep "\[$1\]" -A $CONFIG_FILE_LINE -m 1 | sed -n '2,$p' | while read LINE
    do
        # 下一个配置块就退出
        if [ -n "`echo $LINE|grep -P "^\[[\w-]+\].*"`" ]; then
            break;
        fi
        # 注释或空行就进入下一次循环
        if echo "$LINE"|grep -qP "^((\s*#.*)|([\t\n\s\r]*))$" || [ -z "$LINE" ]; then
            continue;
        fi
        $2 $LINE
    done
}
# 获取文件长度
CONFIG_FILE_LINE=`wc -l $ARGV_config|grep -P '\d+' -o`
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    read_config install install_server
fi

