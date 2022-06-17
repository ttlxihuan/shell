#!/bin/bash
# 服务启停管理，此脚本主要针对批量配置服务管理
# 传入对应的操作功能即可

# 参数信息配置
SHELL_RUN_DESCRIPTION='服务启停管理'
SHELL_RUN_HELP="
查看服务状态：
    bash $0 name
        name    服务名

重启服务：
    bash $0 name restart
        name    服务名

操作所有服务服务：
    bash $0 @ALL action
        action  操作名

安装脚本安装后会自动写入服务处理配置，方便服务启停操作。
允许手动添加一些服务启动，服务可以增加为多个。
"
DEFINE_TOOL_PARAMS='
[action="status", {required}]操作名，默认为 status
#   start       启动服务
#   restart     重启服务
#   stop        停止服务
#   status      获取服务运行状态
[name]要操作的服务名，多个使用逗号分开。
#不指定为全部配置服务处理
[-f, --conf="etc/services.conf", {required|file}]指定配置文件，相对脚本根目录
'

source ${CURRENT_SHELL_BASH}includes/tool.sh || exit

# 操作服务
# @command handle_service $name
# @param $name          要操作的服务名
# return 0|1
handle_service(){
    if ! has_conf "$1";then
        error_exit "未知服务：$1";
    fi
    local HANDLE_INFO
    get_conf HANDLE_INFO "$1" info
    tag_msg "${HANDLE_INFO:-$1}"
    handle_run "$1" "$ARGU_action"
}
# 操作处理
# @command handle_run $name $action
# @param $name          要操作的服务名
# @param $action        要操作动作名
# return 0|1
handle_run(){
    local RUN_COMMAND
    case "$2" in
        start)
            if handle_run "$1" status >/dev/null;then
                warn_msg "服务已经启动"
                return 1
            else
                # 获取重动命令
                if get_conf RUN_COMMAND "$1" "start-run"; then
                    run_msg "$RUN_COMMAND"
                else
                    error_exit "没有配置启动命令";
                fi
            fi
        ;;
        restart)
            # 获取重启命令
            if get_conf RUN_COMMAND "$1" "restart-run"; then
                run_msg "$RUN_COMMAND"
            else
                handle_run "$1" stop
                handle_run "$1" start
            fi
        ;;
        stop)
            if ! handle_run "$1" status >/dev/null;then
                warn_msg "服务未启动"
                return 1
            fi
            # 获取停止命令
            if get_conf RUN_COMMAND "$1" "stop-run"; then
                run_msg "$RUN_COMMAND"
            else
                # 获取进程PID命令
                local PID_NUM
                get_handle_pid PID_NUM "$1"
                run_msg kill $PID_NUM
                info_msg "获取关闭结果："
                local LOOP_NUM=30
                # 循环获取关闭结果
                while handle_run "$1" status >/dev/null;do
                    sleep 1
                    printf '.'
                    if [ "$LOOP_NUM" == '10' ];then
                        warn_msg "服务还在继续，尝试强制关闭"
                        run_msg kill -9 $PID_NUM
                        info_msg "获取关闭结果："
                    elif [ "$LOOP_NUM" = '0' ];then
                        error_exit "服务关闭失败"
                    fi
                    ((LOOP_NUM--))
                done
            fi
        ;;
        status)
            # 获取状态命令
            if get_conf RUN_COMMAND "$1" "status-run"; then
                run_msg "$RUN_COMMAND"
            else
                # 获取进程PID命令
                local PID_NUM
                get_handle_pid PID_NUM "$1"
                info_msg "服务运行中"
            fi
        ;;
        *)
            error_exit "未知操作名：$2"
        ;;
    esac
}
# 获取操作处理PID
# @command get_handle_pid $set_value $name
# @param $set_value     获取写入变量
# @param $name          服务名
# return 0|1
get_handle_pid(){
    # 获取进程PID命令
    local PID_NUM
    if get_conf RUN_COMMAND "$1" "pid-run"; then
        PID_NUM=$(eval "$RUN_COMMAND")
    else
        # 获取进程PID文件
        local PID_FILE
        if get_conf PID_FILE "$1" "pid-file" && [ -n "$PID_FILE"  -a -e "$PID_FILE" ];then
            PID_NUM=$(cat $PID_FILE)
        fi
    fi
    if [[ "$PID_NUM" =~ ^[1-9][0-9]*$ ]] && [ ! -d "/proc/$PID_NUM/" ];then
        error_exit "无法获取服务 ${1} 的PID"
    fi
    eval "$1=$PID_NUM"
}

if ! [[ "$ARGU_action" =~ ^(start|restart|stop|status)$ ]];then
    error_exit "未知操作名：$ARGU_action"
fi
# 配置文件解析
parse_conf $ARGV_conf

if [ -z "$ARGU_name" ];then
    # 全部处理
    each_conf handle_service
else
    # 单独处理
    handle_service "$ARGU_name"
fi
