#!/bin/bash
#
# 批量安装服务

# 参数信息配置
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    SHELL_RUN_DESCRIPTION='批量安装'
fi
SHELL_RUN_HELP='
1、批量安装仅限支持的脚本，多个安装并行操作
2、批量安装默认会忽略磁盘空间（建议磁盘剩余空间 >= 50G）
3、批量安装默认会自动适配虚拟内存，当物理内存不足时自动添加虚拟内存
'$SHELL_RUN_HELP
DEFINE_TOOL_PARAMS="
[name, {required}]要安装的包或组名，多个使用逗号分开
#包或组名必需在配置文件中指定
[-f, --conf='etc/install-batch.conf', {required|file}]指定配置文件，相对脚本库根目录
$DEFINE_TOOL_PARAMS
"
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../includes/tool.sh || exit
# 运行安装操作
# @command run_install $name
# @param $name              要安装的包或组名，多个使用逗号分开
# return 1|0
run_install(){
    if (( (RUN_INSTALL_RECURSION++) > 10 ));then
        error_exit "$1 递归安装已经超过10层，请确认配置是否异常"
    fi
    local NAME INSTALL_INFO LOG_FILE
    # 循环提取要安装的包名
    while read NAME ;do
        if [[ "$NAME" == @* ]];then
            get_conf INSTALL_INFO install-group "${NAME#*@}"
            run_install "$INSTALL_INFO"
        else
            get_conf INSTALL_INFO install "$NAME"
            if [ -z "$INSTALL_INFO" ];then
                INSTALL_INFO="$NAME"
            fi
            if ! [[ "${INSTALL_INFO#* }" =~ [[:space:]]+[^[:space:]]+ ]];then
                INSTALL_INFO="$INSTALL_INFO new"
            fi
            NAME=${INSTALL_INFO%% *}
            find_project_file install "${NAME}" INSTALL_FILE_PATH
            if has_run_shell "${NAME}-install"; then
                warn_msg "${NAME} 已经在安装运行中"
            else
                install_log_file LOG_FILE "${NAME}"
                info_msg "安装 ${NAME} 标准输出信息保存在：$LOG_FILE"
                run_msg "bash $INSTALL_FILE_PATH ${INSTALL_INFO#* } --disk-space=ignore --memory-space=swap >$LOG_FILE 2>&1" && echo '安装 ${NAME} 成功' &
            fi
        fi
    done <<EOF
$(printf '%s' "$1"|grep -oP '[^,\s]+')
EOF
}
# 获取安装日志文件
# @command install_log_file $set_value $name
# @param $set_value         要写入变量名
# @param $name              安装信息名
# return 1|0
install_log_file(){
    eval $1="$SHELL_WROK_TEMP_PATH/${2}-install-$(date +'%Y-%m-%d').log"
    echo '[安装时间]'$(date +'%Y-%m-%d %H:%M:%S') >> $1
}
# 开始批量安装操作
# @command start_install $wait
# @param $wait              是否等待安装完成
#                           任何非空字符均表示等待批量安装完成
# return 1|0
start_install(){
    info_msg "开始本地批量安装"
    # 执行安装
    run_install "$ARGU_name"
    info_msg "所有安装包命令已经在后台并行执行中"
    if [ -n "$1" ];then
        info_msg "等待本地所有批量安装子进程结束"
        wait
    fi
}
# 安装递归调用层次
RUN_INSTALL_RECURSION=0
# 配置文件解析
parse_conf $ARGV_conf install install-group remote $CONF_BLOCKS
# 如果是当前脚本为入口文件则为本地批量安装
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    start_install 1
fi
