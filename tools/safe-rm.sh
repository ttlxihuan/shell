#!/bin/bash
# 都应该知道 rm -rf /* 类似命令的危害（还有 mv 命令）
# 不要问我为什么要做这个脚本，反正我将会在我的服务器里全面使用这个脚本
# 此脚本会生成一个代理rm脚本替代
# 注意：如果真不小心删除了系统核心或重要文件，立即停止写文件操作（有条件可以快照备份），或者停机然后挂载到其它服务器上进行恢复，
# 如需要恢复文件或分区可使用免费工具 testdisk ，此工具是全英文界面，操作前需要确认好相关功能
# 恢复并不能保证绝对，所有恢复是利用系统删除文件只是从文件表中删除实际文件内容并未删除，但很容易被覆蓋导致恢复失败，如果是系统盘被删除恢复的机率更小
# 亡羊补牢还不如提前限制死，类似脚本还有很多

# 参数信息配置
SHELL_RUN_DESCRIPTION='安全删除命令'
SHELL_RUN_HELP="
此脚本会自动生成rm和mv命令的代理脚本，能防止运行删除敏感目录或文件。
删除或移动操作往往是不经意的，但造成的后果却是沉重的。
"
DEFINE_RUN_PARAMS='
[action, {required|in:install,uninstall,reinstall}]脚本处理动作：
#  install    安装
#  uninstall  卸载
#  reinstall  重安装
[--skip-rm]跳过处理rm命令安装或卸载
[--skip-mv]跳过处理mv命令安装或卸载
[--rename-prefix="danger-"]重命名对应系统命令前缀（将原来命令增加前缀）。
#重命名可防止直接使用系统命令。
'
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit

# 代理处理脚本
AGENT_SHELL_PATH=/usr/local/safe-agent-run.sh
AGENT_CONF_PATH=/etc/safe-rm.conf
AGENT_COMMAND_DIR=/usr/sbin/

# 重命名系统命令
# @command rename_sys_command $source $target
# @param $source      现命令名
# @param $target      目标命令名
# return 1|0
rename_sys_command(){
    local _INDEX _COMMAND _SYS_COMMAND_PATHS=()
    search_sys_command $1 _SYS_COMMAND_PATHS
    for ((_INDEX=0;_INDEX<${#_SYS_COMMAND_PATHS[@]};_INDEX++)); do
        _COMMAND=${_SYS_COMMAND_PATHS[$_INDEX]}
        if [ -e $(dirname $_COMMAND)/$2 ];then
            error_exit "已经存在 $2 命令，终止操作"
        else
            rename $(basename $_COMMAND) $2 $_COMMAND
        fi
    done
}
# 搜索指定系统命令
# @command search_sys_command $name $var_array $exist
# @param $name          要搜索的命令名
# @param $var_array     写入数组变量名
# return 1|0
search_sys_command(){
    local _COMMAND 
    while read _COMMAND; do
        if [[ "$(file --mime-type "$_COMMAND" 2>/dev/null)" == *application/x-executable ]];then
            eval "$2[\${#$2[@]}]"="\$_COMMAND"
        fi
    done <<EOF
$(which -a $1 2>/dev/null)
EOF
    if eval "((\${#$2[@]} < 1))";then
        error_exit "没有找到 $1 命令，终止操作"
    fi
}
# 安装指定系统代理命令
# @command install_agent_command $name
# @param $name          要安装代理的命令名
# return 1|0
install_agent_command(){
    if check_install_agent_command $1;then
        warn_msg "检测到已经安装了代理命令 $1"
        return 1
    fi
    [ -n "${ARGV_rename_prefix}" ] && rename_sys_command $1 ${ARGV_rename_prefix}$1
    local _SYS_COMMAND_PATHS=()
    search_sys_command ${ARGV_rename_prefix}$1 _SYS_COMMAND_PATHS 1
    cat > $AGENT_COMMAND_DIR$1 <<EOF
#!/bin/bash
# 代理命令，当命令操作限制目录时终止命令继续，防止核心目录或文件被破坏
( source "$AGENT_SHELL_PATH"; eval ${_SYS_COMMAND_PATHS[0]} \$ARGVS_STR )
EOF
    chmod +x $AGENT_COMMAND_DIR$1
    info_msg "安装 $1 代理命令成功"
}
# 卸载指定系统代理命令
# @command uninstall_agent_command
# return 1|0
uninstall_agent_command(){
    local _COMMAND
    if [ -n "${ARGV_rename_prefix}" ];then
        for _COMMAND in ${AGENT_COMMANDS[@]};do
            if check_install_agent_command $_COMMAND;then
                rename_sys_command ${ARGV_rename_prefix}$_COMMAND $_COMMAND
            fi
        done
    fi
    local _SYS_COMMAND_PATHS=()
    search_sys_command rm _SYS_COMMAND_PATHS 1
    for _COMMAND in ${AGENT_COMMANDS[@]};do
        if check_install_agent_command $_COMMAND;then
            ${_SYS_COMMAND_PATHS[0]} -f $AGENT_COMMAND_DIR$_COMMAND
            info_msg "卸载 $1 代理命令成功"
        else
            warn_msg "未找到代理命令 $_COMMAND"
        fi
    done
    if (( ${#AGENT_COMMANDS[@]} >= 2));then
        [ -e $AGENT_CONF_PATH ] && ${_SYS_COMMAND_PATHS[0]} -f $AGENT_CONF_PATH
        [ -e $AGENT_SHELL_PATH ] && ${_SYS_COMMAND_PATHS[0]} -f $AGENT_SHELL_PATH
    fi
}
# 检测脚本
# @command check_install_agent_command $name
# @param $name          脚本名
# return 1|0
check_install_agent_command(){
    [[ "$(file --mime-type "$AGENT_COMMAND_DIR$1" 2>/dev/null)" == *text/x-shellscript ]];
    return $?
}

# 要处理的代理命令
AGENT_COMMANDS=()
if [ -z "$ARGV_skip_rm" ];then
    AGENT_COMMANDS[${#AGENT_COMMANDS[@]}]=rm
fi
if [ -z "$ARGV_skip_mv" ];then
    AGENT_COMMANDS[${#AGENT_COMMANDS[@]}]=mv
fi
#========= 重装处理 =========
if [ "$ARGU_action" = 'reinstall' ];then
    uninstall_agent_command
fi
#========= 卸载处理 =========
if [ "$ARGU_action" = 'uninstall' ];then
    uninstall_agent_command
    exit
fi
#========= 安装处理 =========
# 配置文件
if [ -e $AGENT_CONF_PATH ];then
    warn_msg "已经存在配置文件 $AGENT_CONF_PATH"
else
    cat > $AGENT_CONF_PATH <<CMD
# 安全目录配置，配置后将无法进行删除和移动
# 配置规则： 
#     /           匹配      / 和 /* 相对路径 ./*
#     /usr/*      匹配      /usr/* 即/usr及子目录
#     /*/bin/     匹配      所有携带 bin/ 或 bin/* 
#     /usr/bash   匹配      /usr/bash 文件
# 所有限制目录最好以绝对路径开始，配置后将无法使用正常命令进行删除或移动
# 配置不宜过多，否则会影响删除性能
# 如果指定的目录不存在，则配置无效

/
/bin/*
/boot/*
/dev/*
/etc/
/lib/
/lib64/
/media/
/mnt/*
/opt/
/proc/*
/sbin/*
/selinux/
/srv/
/sys/*
/usr/
/usr/bin/*
/usr/sbin/*
/usr/lib/
/usr/lib64/
/var/
/run/
CMD
fi
# 复制安全脚本
if [ ! -e $AGENT_SHELL_PATH ];then
    # 写入参数处理脚本
    cat > "$AGENT_SHELL_PATH" <<BASH
#!/bin/bash
############################################################################
# 此脚本是代理命令过滤处理部分，当操作的目录在配置中指定则会终止脚本并提示
# 脚本不参与命令操作，主要提供给其它命令安全报警，当报警后终止执行其它命令即可保证命令执行的安全性
# 所代理命令必需是操作目录命令，否则特殊参数会被认为为目录进行判断处理
#
# 推荐使用方式：（独立运行脚本）
#   (source safe-agent-run.sh; command \$ARGVS_STR)
############################################################################
# 解析出禁止通配所有
DISABLED_ALL_ITEMS=()
# 解析出禁止相同路径
DISABLED_EQUAL_ITEMS=()
# 获取绝对路径
# @command get_realpath \$pathname \$title \$get_file
# @param \$pathname        一级目录名
# @param \$title           脚本集标题名
# @param \$get_file        获取文件
# return 0|1
get_realpath(){
    local _REALPATH
    if [ -d "\${1}" ];then
        _REALPATH="\${1}"
    else
        _REALPATH=\$(cd "\$(dirname "\${1}")";pwd)'/'
    fi
    if [ "\${_REALPATH:0:1}" != '/' ];then
        _REALPATH=\$(cd "\${_REALPATH}";pwd)'/'
    fi
    if [ -n "\$3" -a ! -d "\${1}" ];then
        _REALPATH="\$_REALPATH\$(basename "\${1}")"
    fi
    eval \$2=\\\${_REALPATH}
}
# 匹配禁止操作目录
# @command match_disabled \$source \$target \$wildcard
# @param \$source            源目录
# @param \$target            目标目录
# @param \$wildcard          是否通配
# return 0|1
match_disabled(){
    local DISABLED_PATH
    if (( \${#1} < \${#2} ));then
        # 源目录长度小于于目标目录长度
        [ "\$1" = "\${2:0:\${#1}}" ]
    elif (( \${#1} > \${#2} ));then
        # 源目录长度大于目标目录长度
        [ "\$3" = '1' -a  "\${1:0:\${#2}}" = "\$2" ]
    else
        # 目录长度相等
        [ "\$1" = "\$2" ]
    fi
    if [ \$? = '0' ];then
        echo "操作位置 \${1} 在禁止区域 \${2}，终止操作！"
        exit 1
    fi
}
# 配置提取
while read -r _CONF;do
    # 跳过注释
    if [[ "\${_CONF}" =~ ^[[:space:]]*(#.*)?$ ]];then
        continue
    fi
    # 提取目录
    FIND_PATH=\$(find \$_CONF -maxdepth 1 2>/dev/null | head -n 1)
    # 解析出来为空就跳过
    if [ -z "\$FIND_PATH" ];then
        continue
    fi
    # 处理目录
    get_realpath "\$FIND_PATH" FIND_PATH
    if [[ "\$_CONF" =~ .*\*[[:space:]]*$ ]];then
        # 禁止所有
        DISABLED_ALL_ITEMS[\${#DISABLED_ALL_ITEMS[@]}]="\$FIND_PATH"
    else
        DISABLED_EQUAL_ITEMS[\${#DISABLED_EQUAL_ITEMS[@]}]="\$FIND_PATH"
    fi
done <<EOF
\$(cat /etc/safe-rm.conf)
EOF
# 直接使用入口文件名调用会在source内部自动增加 -i 参数，必需在处理前校验并剥离掉
# 如果非直接调用不建议单独使用-i参数在前面否则会被剥离
if [ "\$1"  = '-i' ];then
    shift
fi
# 目录参数匹配
ARGVS_STR=''
for AVG_ITEM; do
    # 参数组装，方便特殊参数
    ARV_ITEM=\${AVG_ITEM//\\\\/\\\\\\\\}
    ARV_ITEM=\${ARV_ITEM//\"/\\\\\\"}
    ARGVS_STR="\$ARGVS_STR "'"'\$ARV_ITEM'"'
    # 选项参数不需要
    if [ "\${AVG_ITEM:0:1}" = '-' ];then
        continue
    fi
    while read -r FIND_PATH; do
        # 处理目录
        get_realpath "\$FIND_PATH" FIND_PATH 1
        for ((_INDEX=0;_INDEX<\${#DISABLED_EQUAL_ITEMS[@]};_INDEX++));do
            match_disabled "\$FIND_PATH" "\${DISABLED_EQUAL_ITEMS[\$_INDEX]}"
        done
        for ((_INDEX=0;_INDEX<\${#DISABLED_ALL_ITEMS[@]};_INDEX++));do
            match_disabled "\$FIND_PATH" "\${DISABLED_ALL_ITEMS[\$_INDEX]}" 1
        done
    done <<EOF
\$(find "\$AVG_ITEM" -maxdepth 1 2>/dev/null | head -n 1)
EOF
done

BASH
    if_error "写入处理脚本失败，请确认磁盘空间或操作权限"
fi

# 逐个安装处理
for _COMMAND in ${AGENT_COMMANDS[@]};do
    install_agent_command $_COMMAND
done
