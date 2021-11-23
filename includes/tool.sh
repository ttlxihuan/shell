#!/bin/bash
############################################################################
# 工具脚本公共处理文件，所有工具脚本运行的核心文件
# 此脚本不可单独运行，需要在其它脚本中引用执行
# 引用此脚本需要配置以下变量
#   SHELL_RUN_DESCRIPTION   脚本功能说明，帮助信息展示
#   SHELL_RUN_HELP          脚本附加说明，帮助信息展示，可选
#   DEFINE_TOOL_PARAMS      脚本参数体，解析参数使用，可选
# 所有脚本会强制增加两个参数 --help、--version 用来展示信息
############################################################################
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    error_exit "$(realpath "${BASH_SOURCE[0]}") 脚本是共用文件必需使用source调用"
fi
# 引用公共文件
source $(realpath ${BASH_SOURCE[0]}|sed -r 's/[^\/]+$//')basic.sh || exit
# 获取文件全路径
# @command get_file_path $path $var_name $exist
# @param $path              文件名
# @param $var_name          全路径写入变量名
# @param $exist             验证文件存在
# return 1|0
get_file_path(){
    local REALPATH_STR
    if [ -z "$1" ];then
        return 1
    elif [ ${1:0:1} = ':' ];then
        REALPATH_STR=$SHELL_WROK_BASH_PATH/${1:1}
    else
        REALPATH_STR=$1
    fi
    REALPATH_STR=$(realpath $REALPATH_STR)
    if [ -n "$3" -a ! -e "$REALPATH_STR" ];then
        return 1
    fi
    eval "$2=$REALPATH_STR"
}
# 解析工具脚本参数
parse_command_param DEFINE_TOOL_PARAMS CALL_INPUT_ARGVS
