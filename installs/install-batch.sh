#!/bin/bash
# 本地批量安装工具
# 批量安装依赖配置文件

# 参数信息配置
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    SHELL_RUN_DESCRIPTION='批量安装'
fi
SHELL_RUN_HELP='1、批量安装仅限支持的脚本，多个安装并行操作
2、批量安装默认会忽略磁盘空间（建议磁盘剩余空间 >= 50G）
3、批量安装默认会自动适配虚拟内存，当物理内存不足时自动添加虚拟内存
'$SHELL_RUN_HELP
DEFINE_TOOL_PARAMS="
[name, {required}]要安装的包或组名，多个使用逗号分开
#包或组名必需在配置文件中指定
#组名必需是@+组合形式，否则按包名处理
[-f, --conf='etc/install-batch.conf', {required|file}]指定配置文件，相对脚本库根目录
[-c, --check-install]验证批量安装结果信息
$DEFINE_TOOL_PARAMS
"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit
# 循环获取安装信息并调用指定函数
# @command each_install $name $func
# @param $name              要循环安装的包或组名，多个使用逗号分开
# @param $func              调用的函数名
# return 1|0
each_install(){
    if (( (RUN_INSTALL_RECURSION++) > 10 ));then
        error_exit "$1 递归安装已经超过10层，请确认配置是否异常"
    fi
    local NAME INSTALL_INFO
    # 循环提取要安装的包名
    while read NAME ;do
        if [[ "$NAME" == @* ]];then
            get_conf INSTALL_INFO install-group "${NAME#*@}"
            each_install "$INSTALL_INFO" $2
        else
            get_conf INSTALL_INFO install "$NAME"
            if [ -z "$INSTALL_INFO" ];then
                INSTALL_INFO="$NAME"
            fi
            if ! [[ "${INSTALL_INFO#* }" =~ [[:space:]]+[^[:space:]]+ ]];then
                INSTALL_INFO="$INSTALL_INFO new"
            fi
            NAME=${INSTALL_INFO%% *}
            if has_run_shell "${NAME}-install"; then
                warn_msg "${NAME} 在安装运行中"
            else
                # 调用函数处理
                $2 $INSTALL_INFO
            fi
        fi
    done <<EOF
$(printf '%s' "$1"|grep -oP '[^,\s]+')
EOF
}
# 运行安装操作
# @command run_install $name
# @param $name              要安装的包或组名，多个使用逗号分开
# return 1|0
run_install(){
    # 获取日志文件名
    local LOG_FILE="$SHELL_WROK_TEMP_PATH/${1}-install-$(date +'%Y-%m-%d_%H_%M_%S').log"
    # 获取脚本文件名路径
    find_project_file install "${1}" INSTALL_FILE_PATH
    info_msg "安装 ${1} 标准输出信息保存在：$LOG_FILE"
    run_msg "nohup bash $INSTALL_FILE_PATH ${@:2} --disk-space=ignore --memory-space=swap >$LOG_FILE 2>&1 &"
}
# 验证批量安装结果
# @command check_install
# return 1|0
check_install(){
    local INSTALL_RESULT INSTALL_STATUS LOG_FILE
    for LOG_FILE in $(find "$SHELL_WROK_TEMP_PATH" -name "${1}-install-*.log"|sort -r|head -n 1);do
        tag_msg "${1} $(echo "$LOG_FILE"|grep -oP '\d{4}(-\d{1,2}){2}(_\d{1,2}([:_]\d{1,2}){2})?'|tail -n 1|sed -e 's/_/ /' -e 's/_/:/g')" '*' 60
        INSTALL_RESULT=$(tail -n 1 $LOG_FILE)
        if [[ "$INSTALL_RESULT" =~ \[SHELL-[A-Z]+\] ]];then
            INSTALL_STATUS=${INSTALL_RESULT#*[}
            INSTALL_STATUS=${INSTALL_STATUS%%]*}
        else
            INSTALL_STATUS='UNKNOWN'
        fi
        print_msg "${INSTALL_STATUS#*-}" "${INSTALL_RESULT#*]}"
    done
    [ -z "$LOG_FILE" ] && warn_msg "没有 $1 安装信息"
}
# 开始批量安装操作
# @command start_install
# return 1|0
start_install(){
    # 安装递归调用层次
    local RUN_INSTALL_RECURSION=0
    if [ -n "$ARGV_check_install" ];then
        each_install "$ARGU_name" check_install
    else
        # 执行安装
        each_install "$ARGU_name" run_install
    fi
}
# 配置文件解析
parse_conf $ARGV_conf install install-group remote $CONF_BLOCKS
# 如果是当前脚本为入口文件则为本地批量安装
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    start_install
fi
