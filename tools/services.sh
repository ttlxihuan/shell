#!/bin/bash
# 服务启停管理
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
[name]要操作的服务名，多个使用逗号分开。
#当需要全部启动时是传 @ALL
[action]操作名，默认为 status
#   start
#   restart
#   stop
#   status
[-f, --conf="etc/services.conf", {required|file}]指定配置文件，相对脚本根目录
'
if (( $# == 0 ));then
    ARGV_help=1
fi

source ${CURRENT_SHELL_BASH}includes/tool.sh $1 || exit

# 提取配置文件路径
if ! get_file_path $ARGV_conf ARGV_conf 1;then
    error_exit "--conf 未指定有效配置文件：$ARGV_conf"
fi
# 操作服务
# @command handle_service $name $action
# @param $name          要操作的服务名
# @param $action        操作名
# return 0|1
handle_service(){
    local NAME=SERVICE_$(echo "$1"|md5sum -t|tr '[:lower:]' '[:upper:]') RUN_STATUS_VAL=''
    if(( $(eval \${#$NAME[0]}) <= 1 ));then 
        error_exit "未知服务：$1";
    else
        info_msg "$(eval \${$NAME[$INFO_KEY]})"; 
    fi
    case "$2" in
        start)
            if handle_service $1 status >/dev/null;then
                warn_msg "服务已经启动"
            else
                local START_RUN=$(eval \${$NAME[$START_RUN_KEY]}); 
                if [ -n "$START_RUN" ];then
                    eval "$START_RUN"
                    if [ "$?" = '0' ];then
                        info_msg "启动服务成功"
                    else
                        error_exit "启动服务失败"
                    fi
                else
                    error_exit "没有配置启动命令"
                fi
            fi
        ;;
        restart)
            local RESTART_RUN=$(eval \${$NAME[$RESTART_RUN_KEY]}); 
            if [ -n "$RESTART_RUN" ];then
                eval "$RESTART_RUN"
                if [ "$?" = '0' ];then
                    info_msg "重启服务成功"
                else
                    error_exit "重启服务失败"
                fi
            else
                handle_service $1 stop
                handle_service $1 start
            fi
        ;;
        stop)
            if ! handle_service $1 status >/dev/null;then
                warn_msg "服务未启动"
                return 1
            fi
            local STOP_RUN=$(eval \${$NAME[$STOP_RUN_KEY]}); 
            if [ -n "$STOP_RUN" ];then
                eval "$STOP_RUN"
                RUN_STATUS_VAL=$?
            else
                local PID_NUM PID_RUN=$(eval \${$NAME[$PID_RUN_KEY]});
                if [ -n "$PID_RUN" ];then
                    PID_NUM=$(eval "$PID_RUN")
                else
                    local PID_FILE=$(eval \${$NAME[$PID_FILE_KEY]});
                    if [ -n "$PID_FILE"  -a -e "$PID_FILE" ];then
                        PID_NUM=$(cat $PID_FILE)
                    else
                        error_exit "缺少获取PID配置，无法关闭服务"
                    fi
                fi
                if [[ "$PID_NUM" =~ ^[1-9][0-9]*$ ]];then
                    run_msg kill $PID_NUM
                    info_msg "获取关闭结果："
                    local LOOP_NUM=30
                    # 循环获取关闭结果
                    while handle_service $1 status >/dev/null;do
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
                    info_msg "服务关闭成功"
                    return 0
                else
                    error_exit "获取PID值错误：$PID_NUM，无法关闭服务"
                fi
            fi
            if [ "$RUN_STATUS_VAL" = '0' ];then
                info_msg "服务关闭成功"
            else
                error_exit "服务关闭失败"
            fi
        ;;
        status)
            local STATUS_RUN=$(eval \${$NAME[$STATUS_RUN_KEY]});
            if [ -n "$STATUS_RUN" ];then
                eval "$STATUS_RUN"
                RUN_STATUS_VAL=$?
            else
                local PID_RUN=$(eval \${$NAME[$PID_RUN_KEY]});
                if [ -n "$PID_RUN" ];then
                    eval "$PID_RUN"
                    RUN_STATUS_VAL=$?
                else
                    local PID_FILE=$(eval \${$NAME[$PID_FILE_KEY]});
                    if [ -n "$PID_FILE" ];then
                        test -e "$PID_FILE" -a -d "/proc/$(cat $PID_FILE)/"
                        RUN_STATUS_VAL=$?
                    else
                        error_exit "缺少获取状态配置，无法获取服务运行状态"
                    fi
                fi
            fi
            if [ "$RUN_STATUS_VAL" = '0' ];then
                info_msg "服务运行中"
            else
                info_msg "服务未运行"
            fi
            return $RUN_STATUS_VAL
        ;;
        *)
            error_exit "未知操作名：$ARGU_action"
        ;;
    esac
}
# 解析配置数据
# @command parse_config
# return 0|1
parse_config(){
    local SET_KEY LINE NAME=''
    while read LINE;do
        if [[ "$LINE" =~ ^\s*\[.*?\] ]];then
            NAME=$(echo "$LINE"|grep -oP '\[.*?\]'|sed -r 's/\[\s*|\s*\]//g')
            SERVICE_NAMES[${#SERVICE_NAMES[@]}]="$NAME"
            NAME=SERVICE_$(echo "$NAME"|md5sum -t|tr '[:lower:]' '[:upper:]')
            eval "$NAME=()"
        elif ! [[ "$LINE" =~ ^\s*(info|pid-file|(pid|start|restart|stop|status)-run)\s*= ]];then
            continue
        else
            case ${LINE%=*} in
                info)
                    SET_KEY=INFO_KEY
                ;;
                pid-file)
                    SET_KEY=PID_FILE_KEY
                ;;
                pid-run)
                    SET_KEY=PID_RUN_KEY
                ;;
                start-run)
                    SET_KEY=START_RUN_KEY
                ;;
                stop-run)
                    SET_KEY=STOP_RUN_KEY
                ;;
                restart-run)
                    SET_KEY=RESTART_RUN_KEY
                ;;
                status-run)
                    SET_KEY=STATUS_RUN_KEY
                ;;
                *)
                    warn_msg "示知配置：$LINE"
                    continue
                ;;
            esac
            eval "$NAME[\$SET_KEY]=\${LINE#*=}"
        fi
    done < $ARGV_conf
}

SERVICE_NAMES=() INFO_KEY=0 PID_FILE_KEY=1 PID_RUN_KEY=2 START_RUN_KEY=3 RESTART_RUN_KEY=4 STATUS_RUN_KEY=5 STOP_RUN_KEY=6
if ! [[ "$ARGU_action" =~ ^(start|restart|stop|status)$ ]];then
    error_exit "未知操作名：$ARGU_action"
fi
if [ "$ARGU_name" = '' ];then
    error_exit "服务名为空"
fi
# 配置解析
parse_config
if [ "$ARGU_name" = '@ALL' ];then
    # 全部处理
    for((INDEX=0;INDEX<${#SERVICE_NAMES[@]};INDEX++));do
        handle_service "${SERVICE_NAMES[$INDEX]}" $ARGU_action
    done
else
    # 单独处理
    info_msg "获取服务状态"
    handle_service "$ARGU_name" $ARGU_action
fi
