#!/bin/bash
############################################################################
# 提取$@数据，保存两份数组，一份是直接使用，一份是eval调用命令转义参数
# 脚本处理公共文件，不能单独运行
# 此脚本必需在需要时使用 source 命令引用
############################################################################

if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 如果是函数内部调用则使用局部变量
if has_variable FUNCNAME && (( ${#FUNCNAME[@]} > 2 ));then
    # 定义内部参数
    local CALL_SAFE_ARGVS=() CALL_INPUT_ARGVS=()
else
    # 定义内部参数
    CALL_SAFE_ARGVS=() CALL_INPUT_ARGVS=()
fi
# 提取参数
for _ARV_ITEM_;do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=$_ARV_ITEM_
    _ARV_ITEM_=${_ARV_ITEM_//\\/\\\\}
    _ARV_ITEM_=${_ARV_ITEM_//\"/\\\"}
    CALL_SAFE_ARGVS[${#CALL_SAFE_ARGVS[@]}]=\"$_ARV_ITEM_\"
done
unset _ARV_ITEM_
