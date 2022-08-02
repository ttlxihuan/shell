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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit

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
# 运行命令
# @command run_command $name $command
# @param $name          要操作的服务名
# @param $action        要操作动作名
# return 0|1
run_command(){
    local RUN_COMMAND RUN_USER
    get_conf RUN_USER "$1" "user"
    if get_conf RUN_COMMAND "$1" "$2"; then
        if [ -n "$RUN_USER" ];then
            sudo_msg "$RUN_USER" "$RUN_COMMAND"
        else
            run_msg "$RUN_COMMAND"
        fi
        if [ $? = '0' ];then
            info_msg "$2 操作成功"
        else
            warn_msg "$2 操作失败"
        fi
    else
        error_exit "$1 没有配置 ${2} 命令";
    fi
}
# 操作处理
# @command handle_run $name $action
# @param $name          要操作的服务名
# @param $action        要操作动作名
# return 0|1
handle_run(){
    case "$2" in
        start)
            if handle_run "$1" status >/dev/null;then
                warn_msg "服务已经启动"
                return 1
            else
                local LOOP_NUM
                # 重复多次尝试启动服务
                for ((LOOP_NUM=2;LOOP_NUM<5;LOOP_NUM++)); do
                    # 获取重动命令
                    run_command "$1" "start-run"
                    sleep ${LOOP_NUM}s;
                    if handle_run "$1" status >/dev/null;then
                        break;
                    else
                        warn_msg "第${LOOP_NUM}次尝试启动 $1";
                    fi
                done
            fi
        ;;
        restart)
            # 获取重启命令
            if has_conf "$1" "restart-run";then
                run_command "$1" "restart-run"
            else
                handle_run "$1" stop
                handle_run "$1" start
            fi
        ;;
        stop)
            # 获取停止命令
            if handle_run "$1" status >/dev/null;then
                if has_conf "$1" "stop-run";then
                    run_command "$1" "stop-run"
                else
                    # 获取进程PID命令
                    local RUN_PID
                    if get_handle_pid RUN_PID "$1";then
                        run_msg kill $RUN_PID
                        local LOOP_NUM
                        # 重复多次尝试启动服务
                        for ((LOOP_NUM=1;LOOP_NUM<4;LOOP_NUM++)); do
                            sleep ${LOOP_NUM}s;
                            if handle_run "$1" status >/dev/null;then
                                warn_msg "服务还在继续，尝试强制关闭"
                                run_msg kill -9 $RUN_PID
                            else
                                break
                            fi
                        done
                    fi
                fi
                if handle_run "$1" status >/dev/null;then
                    error_exit "服务停止失败"
                else
                    info_msg "服务停止成功"
                fi
            else
                warn_msg "服务未运行，无需关闭"
            fi
        ;;
        status)
            # 获取状态命令
            if has_conf "$1" "status-run";then
                run_command "$1" "status-run"
            else
                # 获取进程PID命令
                local RUN_PID
                if get_handle_pid RUN_PID "$1";then
                    info_msg "服务运行中"
                    return 0
                fi
                warn_msg "服务未运行"
                return 1
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
    local _PID
    if has_conf "$2" "pid-run";then
        _PID=$(run_command "$2" "pid-run"|tail -n 1)
    else
        # 获取进程PID文件
        local PID_FILE
        if get_conf PID_FILE "$2" "pid-file";then
            if [ -n "$PID_FILE"  -a -e "$PID_FILE" ];then
                _PID=$(cat $PID_FILE)
            fi
        else
            error_exit "未配置PID获取"
        fi
    fi
    if [[ "$_PID" =~ ^[1-9][0-9]*$ && -d "/proc/$_PID/" ]];then
        eval "$1=$_PID"
        return 0
    fi
    return 1
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
