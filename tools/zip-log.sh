#!/bin/bash
#
# 打包压缩日志，用来节省磁盘空间
# 建议添加到定时器中，通过定时压缩处理日志能有效减少日志占用过大磁盘空间
#
# nginx日志处理
#   bash zip-log.sh -p 'log' -r 'nginx' -b '../sbin/nginx -s reload'
#

# 输出帮助信息
show_help(){
    echo "
打包压缩日志

命令：
    $(basename "${BASH_SOURCE[0]}") logdir [...] [-h, -?]
    
参数：
    logdir            	日志目录，只提取指定后缀的文件进行压缩
                        建议使用绝对路径，并且最少指定一个日志目录
                        压缩后文件还保存在日志目录中，可以通过压缩后命令处理
    
选项：
    --log-extension=ext, -p=ext
                        指定日志文件后缀名
                        后缀后不携带.前缀，默认是 log
    --before-run=script, -b=script
                        指定压缩日志前运行命令
                        命令在当前处理的日志目录下运行
    --after-run=script, -a=script
                        指定压缩日志后运行命令
                        命令在当前处理的日志目录下运行
                        可以使用导入变量
                            $ZIP_FILE    压缩后的文件名
    --log-rename=ext, -r=ext
                        在压缩前执行，修改待压缩日志文件后缀修改
                        后缀后不携带.前缀，并且会自动增加 zip. 前缀
                        比如：-r=z 实际改为后缀 zip.z
                        用于部分进程锁定文件
    -h, -?              显示帮助信息

说明：
    此脚本用来打包压缩日志文件，用来最大容量保留日志
	建议通过定时器进行定时触发，保证日志不会占用过多磁盘空间
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1" >&2
    exit 1
}
if_error(){
    if [ $? != 0 ];then
        show_error "$1"
    fi
}
# 参数处理
if [ $# = 0 ];then
    show_help
fi

LOG_EXT=log
LOG_DIRS=()

for ((INDEX=1; INDEX<=$#; INDEX++));do
    PARAM_ITEM=${@:$INDEX:1}
    case "$PARAM_ITEM" in
        -h|-\?)
            show_help
        ;;
        --log-extension|-p)
            ((INDEX++))
            LOG_EXT=${@:$INDEX:1}
        ;;
        --log-extension=*|-p=*)
            LOG_EXT=${PARAM_ITEM#*=}
        ;;
        --before-run|-b)
            ((INDEX++))
            BEFORE_RUN=${@:$INDEX:1}
        ;;
        --before-run=*|-b=*)
            BEFORE_RUN=${PARAM_ITEM#*=}
        ;;
        --after-run|-a)
            ((INDEX++))
            AFTER_RUN=${@:$INDEX:1}
        ;;
        --after-run=*|-a=*)
            AFTER_RUN=${PARAM_ITEM#*=}
        ;;
        --log-rename|-r)
            ((INDEX++))
            LOG_RENAME=${@:$INDEX:1}
        ;;
        --log-rename=*|-r=*)
            LOG_RENAME=${PARAM_ITEM#*=}
        ;;
        *)
            LOG_DIRS[${#LOG_DIRS[@]}]=$PARAM_ITEM
        ;;
    esac
done
if [ ${#LOG_DIRS[@]} = 0 ];then
    show_error "未指定压缩目录"
fi
if [ -z "${LOG_EXT}" ];then
    show_error "日志文件后缀不能为空"
fi
if ! which zip 2>&1 &>/dev/null;then
    show_error "请安装 zip 压缩命令"
fi
ZIP_FILE=$(date +'%Y-%m-%d_%H_%M_%S').zip
for ((INDEX=0; INDEX<${#LOG_DIRS[@]}; INDEX++)); do
    if [ -d "${LOG_DIRS[$INDEX]}" ];then
        LOG_DIR=$(cd "${LOG_DIRS[$INDEX]}"; pwd)
        # 是否修改日志文件名
        if [ -n "${LOG_RENAME}" ];then
            (cd ${LOG_DIR}; find ./ -name "*.${LOG_EXT}"|while read LOGFILE;do
                echo "$LOGFILE"
                mv $LOGFILE ./$(basename $LOGFILE ".${LOG_EXT}").zip.${LOG_RENAME}
            done)
            LOG_EXTNAME=zip.${LOG_RENAME}
        else
            LOG_EXTNAME=$LOG_EXT
        fi
        # 压缩前执行
        if [ -n "${BEFORE_RUN}" ];then
            (cd ${LOG_DIR}; eval ${BEFORE_RUN})
        fi
        echo "[info] 压缩目录日志：$LOG_DIR"
        (cd ${LOG_DIR}; find ./ -name "*.${LOG_EXTNAME}" -exec zip -q -u "./$ZIP_FILE" {} \;)
        # 压缩后执行
        if [ -n "${AFTER_RUN}" ];then
            (cd ${LOG_DIR};export ZIP_FILE; eval ${AFTER_RUN})
        fi
    else
        echo "[warn] 不存在日志目录 ${LOG_DIRS[$INDEX]}"
    fi
done
