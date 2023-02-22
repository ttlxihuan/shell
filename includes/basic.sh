#!/bin/bash
############################################################################
# 脚本处理公共文件，所有脚本运行的核心
# 此脚本不可单独运行，需要在其它脚本中引用执行
# 脚本常规要求：
#   1、目录尽可能使用引号，避免目录中包含特殊字符影响命令处理
#   2、一些不能确定字符串可能包含特殊字符除非有特殊要求，都要求使用引号
#   3、尽量使用内置功能命令
#   4、常规命令参数尽量分开写，避免一些命令不支持选项混合导致命令作用不合意
############################################################################
# 全局版本号
readonly SHELL_RUN_VERSION='1.0.3'

# 切换工作目录
# @command chdir $path
# @param $path      切换的子目录
# return 1|0
chdir(){
    mkdirs "$SHELL_WROK_TEMP_PATH/$1"
    cd "$SHELL_WROK_TEMP_PATH/$1"
}
# 递归创建目录
# @command mkdirs $path [$user]
# @param $path      创建的目录
# @param $user      指定目录所有者用户
# return 1|0
mkdirs(){
    if [ ! -d "$1" ];then
        mkdir -p "$1"
        if_error "创建目录失败: $1"
    fi
    if [ -n "$2" ];then
        chown -R $2:$2 "$1"
    fi
    return 0
}
# 判断是否存在指定用户或组
# @command has_user $user
# @param $user          用户名
# return 1|0
has_user(){
    id "$1" >/dev/null 2>/dev/null
}
# 判断上一个命令的成功与否输出错误并退出
# @command if_error $error_str
# @param $error_str     错误内容
# return 1|0
if_error(){
    if [ $? -ne 0 ];then
        error_exit "$1"
    fi
    return 0
}
# 输出错误并退出
# @command error_exit $error_str
# @param $error_str     错误内容
# return 1
error_exit(){
    print_msg ERROR "$@" >&2
    exit 1
}
# 输出常规信息
# @command info_msg $msg
# @param $msg       信息内容
# return 1
info_msg(){
    print_msg INFO "$@"
}
# 输出警告信息
# @command warn_msg $msg
# @param $msg       信息内容
# return 1
warn_msg(){
    print_msg WARN "$@"
}
# 输出动态变化信息，输出信息不会换行并且只会在同一行重写（类似刷新这行内容如同动态变动信息）
# 当输出空内容时结束此行信息，或者使用其它输出函数也将自动结束
# @command live_msg $msg
# @param $msg       信息内容
# return 1
live_msg(){
    print_msg LIVE "$@"
}
# 运行命令输出信息
# @command run_msg $command
# @param $command       执行命令
# return 1
run_msg(){
    print_msg RUN "$@"
    eval $@
}
# 使用指定用户运行命令并输出信息
# 特别注意：
#       /etc/sudoers 配置不可随意将其它账户指定为NOPASSWD，会存在很大的安全隐患
#       如果配置其它账号则root账号最好设置复杂的密码，并且定期更换
#       如果需要增加账号需要修改 /etc/sudoers 配置增加 
#           username ALL=(ALL) ALL
#           或者
#           username ALL=命令目录集
#       也可以指定用户组
# @command sudo_msg $user $command
# @param $user          执行命令的用户
# @param $command       执行命令
# return 1
sudo_msg(){
    local CURRENT_USERNAME=$(whoami)
    if [ "$CURRENT_USERNAME" != 'root' ];then
        warn_msg "非root用户运行sudo，可能导致权限不足运行失败！"
    fi
    # 判断运行sudo权限
    if [ -z "$1" ];then
        error_exit "sudo运行用户为空"
    elif ! has_user "$1";then
        error_exit "sudo运行用户${1}不存在"
    fi
    run_msg sudo -u $1 ${@:2}
}
# 输出左右占位块信息
# @command tag_msg $msg $tag $size $type
# @param $msg           打印信息
# @param $tag           标签符号，默认是 #
# @param $size          总长度，默认100
# @param $type          打印类型，默认是 INFO
# return 1
tag_msg(){
    local TAG_TEXT=${2-#} LINE_SIZE=${3:-100} MSG_TYPE=${4:-TAG} TAG_STR=''
    local DIFF_BOTH=$(( (LINE_SIZE - ${#1} -2) / 2 ))
    if (( DIFF_BOTH > ${#TAG_TEXT} ));then
        TAG_STR="$(printf "%$(( DIFF_BOTH / ${#TAG_TEXT} ))s"|sed "s/ /$TAG_TEXT/g")"
    fi
    print_msg "$MSG_TYPE" "$TAG_STR $1 $TAG_STR"
}
# 输出信息
# @command print_msg $type $msg
# @param $type          打印类型
# @param $msg           打印信息
# @param $msg           打印信息
# @param $msg           打印信息
# return 1
print_msg(){
    if [ "$LIVE_SHOW_STATUS" = '1' ] && ( [  -z "${@:2}" ] || [ "$1" != 'LIVE' ] );then
        unset LIVE_SHOW_STATUS
        echo ''
        if [ "$1" = 'LIVE' ];then
            return
        fi
    fi
    local SHOW_COLOR
    if [ -f /dev/stdout ];then
        # 重定向不需要输出颜色
        echo -n "[SHELL-$1]"
    else
        # echo 打印特殊颜色或控制功能，语法是： \e[action;show-text
        # 语法说明：
        # \e[       功能转义标记开始符，指定功能后的所有文本均生效，其中 \e 也可以使用 \033 替换
        # show-text 要显示的文本内容
        # action;   功能标识符
        #   使用要求：
        #       1、多个功能标识符用分号隔开，没有先后顺序要求（最后一个action不加分号）
        #       2、最后一个标识符结尾加m（功能标记结束符，否则功能异常），echo必需使用-e选项
        #   > 字体颜色功能：（默认白色）
        #       30（黑色）、31（红色）、32（绿色）、33（黄色）、34（蓝色）、35（紫色）、36（天蓝色）、37（白色）
        #   > 字体功能：
        #       1（加粗高亮）、4（下划线）、5（闪烁）、7（反显，字体与背景颜色互换）
        #   > 字体背景颜色功能：（默认黑色）
        #       40（黑色）、41（红色）、42（绿色）、43（黄色）、44（蓝色）、45（紫色）、46（天蓝色）、47（白色）
        #   > 光标功能：（此功能不能与字体相关在一个action中，否则字体相关不起作用）
        #       nA（光标上移n行开始打印）、nB（光标下移n行开始打印）、nC（光标右移n空格开始打印）、nD（光标左移n字符开始打印）、s（保存光标位置）、u（恢复光标位置）
        #       ?25l（隐藏光标）、?25h（显示光标）
        #   > 其它功能：
        #       0（关闭所有功能）、2J（清屏）、K（清除光标到结尾内容）
        #   示例：\e[（下划线+蓝色字体+绿色背景+闪烁）显示内容 \e[（关闭前面所有功能）
        #       echo -e "\e[4;34;42;5mok\e[0m"
        # 特别说明：如果开启了功能未关闭（即：\e[0m）会影响到其它输出，这些功能会一直保留在这个终端进程中
        case "$1" in
            ERROR)
                SHOW_COLOR='31m'
                ;;
            INFO)
                SHOW_COLOR='32m'
                ;;
            WARN)
                SHOW_COLOR='33m'
                ;;
            RUN)
                SHOW_COLOR='34m'
                ;;
            LIVE)
                SHOW_COLOR='35m\r'
                LIVE_SHOW_STATUS=1
                ;;
            *)
                SHOW_COLOR='36m'
                ;;
        esac
        echo -en "\e[40;$SHOW_COLOR[SHELL-$1]\e[0m"
    fi
    if [ "$LIVE_SHOW_STATUS" = '1' ];then
        echo -n " ${@:2}"
    else
        echo " ${@:2}"
    fi
}
# 询问选项处理
# @command ask_select $select_name $msg [$options]
# @param $select_name       询问获取输入内容写入变量名
# @param $msg               询问提示文案
# @param $options           询问输入选项，多个使用/分开，默认是 y/n
# return 1|0
ask_select(){
    local INPUT MSG_TEXT REGEXP_TEXT ATTEMPT=1  OPTIONS=$(printf '%s' "${3-y/n}"|sed 's/ //g')
    MSG_TEXT="$2 请输入：[ $OPTIONS ] "
    REGEXP_TEXT=$(printf '%s' "$OPTIONS"|sed 's/\//|/g')
    while [ -z "$INPUT" ]; do
        read -p "$MSG_TEXT" INPUT
        if printf '%s' "$INPUT"|grep -qP "^($REGEXP_TEXT)$";then
            break
        fi
        INPUT=''
        if ((ATTEMPT >= 10));then
            error_exit "已经连续输入错误 ${ATTEMPT} 次，终止询问！"
        else
            warn_msg "输入错误，请注意输入选项要求！"
            ((ATTEMPT++))
        fi
    done
    eval "$1=\$INPUT"
    return 1
}
# 判断命令是否存在
# @command if_command $name
# @param $name          包名
# return 1|0
if_command(){
    if which "$1" >/dev/null 2>/dev/null;then
        return 0
    fi
    return 1
}
# 询问许可操作
# @command ask_permit $msg
# @param $msg               询问提示文案
# return 1|0
ask_permit(){
    local ASK_INPUT
    ask_select ASK_INPUT "$1" || [ "$ASK_INPUT" = 'y' -o "$ASK_INPUT" = 'Y' ]
    return $?
}
# 生成相对唯一键名
# @command make_key $set_value $name
# @param $set_value         获取写入变量
# @param $name              配置名
# return 1|0
make_key(){
    eval $1=$(printf '%s' "$2"|md5sum -t|awk '{print $1}')
}
# 判断是否存在指定变量
# @command has_variable $var_name
# @param $var_name          要判断的变量名
# return 1|0
has_variable(){
    declare -p $1 >/dev/null 2>/dev/null
}
# 判断是否存在指定函数
# @command has_variable $function_name
# @param $function_name      要判断的函数名
# return 1|0
has_function(){
    declare -F $1 >/dev/null 2>/dev/null
}
# 给指定变量添加转义
# @command addc_slashes $string_name [$character_mask]
# @param $string_name       要转义的字符串变量
# @param $character_mask    要转义的字符串，默认是：\s$~|&()[]"'\
#                           指定多个字符时必需使用|连接
# return 1|0
addc_slashes(){
    local _STRING _MASKS='\s|\$|~|\||&|\(|\)|<|>|\[|\]|\\|"|'"'"
    if [ -n "$2" ];then
        _MASKS=$2
    fi
    eval _STRING=\${$1}
    _STRING=$(printf '%s' "${_STRING}"|sed -r 's/('$_MASKS')/\\\1/g')
    eval $1=\$_STRING
}
# 全路径解析并转义特殊字符
# @command safe_realpath $path
# @param $path              要处理的目录变量名，处理完后会修改此变量
# return 1|0
safe_realpath(){
    local _PATH _NAME
    for _NAME;do
        eval _PATH="\${$_NAME}"
        if [ -z "$_PATH" ];then
            _PATH="$SHELL_WROK_BASH_PATH"
        else
            case "$_PATH" in
                \~|\~/*) # 用户工作目录
                    _PATH="$(cd ~;pwd)/${_PATH:2}"
                ;;
                [^/]*) # 工作目录
                    _PATH="$SHELL_WROK_BASH_PATH/$_PATH"
                ;;
            esac
        fi
        if [ -e "$_PATH" ];then
            _PATH=$(cd "$(dirname "$_PATH")";pwd)/$(basename "$_PATH")
        elif [ -e "$_PATH" ];then
            _PATH=$(cd "$(dirname "$_PATH")";pwd)
        fi
        _PATH=${_PATH//\/\//\/}
        addc_slashes _PATH
        eval $_NAME="\$_PATH"
    done
}
# 解析shell脚本参数
# 命令参数解析成功后将写入参数名规则：
#   参数： ARGU_参数全名
#   选项： ARGV_选项全名
# 横线转换为下划线，缩写选项使用标准选项代替，使用时注意参数名的大小写不变
# @command parse_shell_param $define_name $options_name
# @param $define_name       定义参数变量名
#                           配置参数规则：
#                           [name, {validate}]              定义参数
#                           [name='', {validate}]           定义参数带默认值
#                           [-n, --name, {validate}]        定义无值选项
#                           [-n, --name='', {validate}]     带选项值的选项
#                           说明：
#                           name        参数名，前缀无减号，组合要求：字母、数字、减号
#                           -n          短选项名，前缀一个减号，组合要求：字母、数字、减号
#                                       短选项必需定义在长选项名前面且不可单独定义短选项
#                           --name      长选项名，前缀两个减号，组合要求：字母、数字、减号
#                           =''         定义参数或选项的默认值，选项指定后为带值选项，默认值为空时可省略后面的引号
#                                       默认值允许使用：字母、数字、减号、下划线、转义组合，或者使用单双引号
#                                       转义符在无引号或有引号时均有效使用时需要注意
#                           validate    选项或参数验证，验证支持参考函数 validate_shell_param
# @param $options_name      命令参数数组名
# return 1|0
parse_shell_param(){
    local PARAM NAME SHORT_NAME DEFAULT_VALUE DEFAULT_VALUE_STR DEFAULT_VALIDATE_STR PARAM_STR PARAM_INFO_STR PARAM_NAME_STR PARAM_SHOW_DEFINE PARAM_SHOW_INFO ARG_NAME INDEX 
    local SPACE_NUM=22 ARGUMENTS=() OPTIONS=() OPTIONALS=() ARGVS=() VALIDATES_NAME_QUEUE=() VALIDATES_RULE_QUEUE=() COMMENT_SHOW_ARGUMENTS='' COMMENT_SHOW_OPTIONS=''
    local REGEXP_ARGU='[[:alnum:]][[:alnum:]\-]+' REGEXP_ARGV_SHORT='\-[[:alnum:]]' REGEXP_ARGV_LONG='\-\-[[:alnum:]][[:alnum:]\-]+'
    local REGEXP_ARGV="($REGEXP_ARGV_SHORT\s*,\s*)?$REGEXP_ARGV_LONG|$REGEXP_ARGU" REGEXP_VALIDATE="\{\s*([,:\|]|$REGEXP_QUOTE_STRING)*\s*\}"
    # 解析定义的参数
    while read -r PARAM; do
        if [ -z "$PARAM" ] || printf '%s' "$PARAM"|grep -qP '^\s*$'; then
            continue;
        fi
        if printf '%s' "$PARAM"|grep -qP '^\s*#';then
            PARAM=$(printf '%*s' $SPACE_NUM)"${PARAM:1}\n"
            if [[ "$NAME" == -* ]];then
                COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM"
            elif [ -n "$NAME" ];then
                COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM"
            else
                error_exit "备注无匹配参数信息：$PARAM"
            fi
            continue;
        fi
        # 提取匹配的定义参数语句结构
        PARAM_STR=$(printf '%s' "$PARAM"|grep -oP "^\s*\[\s*($REGEXP_ARGV)(\s*=\s*($REGEXP_QUOTE_STRING)?)?(\s*,\s*$REGEXP_VALIDATE)?\s*\]")
        if [ -z "$PARAM_STR" ];then
            error_exit "定义参数解析失败：$PARAM"
        fi
        # 去掉首尾多余字符
        PARAM_INFO_STR=`printf '%s' "$PARAM_STR"|sed -r "s/(^\s*\[\s*)|(\s*\]\s*$)//g"`
        # 提取参数名定义
        PARAM_NAME_STR=`printf '%s' "$PARAM_INFO_STR"|grep -oP "^($REGEXP_ARGV)"`
        # 提取参数默认值定义
        DEFAULT_VALUE_STR=$(printf '%s' "${PARAM_INFO_STR:${#PARAM_NAME_STR}}"|grep -oP "^\s*=\s*($REGEXP_QUOTE_STRING)?")
        # 提取参数验证规则
        DEFAULT_VALIDATE_STR=$(printf '%s' "${PARAM_INFO_STR}"|grep -oP "$REGEXP_VALIDATE$"|sed -r "s/(^\s*\{\s*)|(\s*\}\s*$)//g")
        # 参数类型识别处理
        if [[ "$PARAM_NAME_STR" =~ ^-{1,2} ]];then
            SHORT_NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oP "^$REGEXP_ARGV_SHORT"`
            NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oP "$REGEXP_ARGV_LONG"`
            PARAM_SHOW_DEFINE="$NAME"
            if [ -n "$SHORT_NAME" ];then
                PARAM_SHOW_DEFINE="$SHORT_NAME, $PARAM_SHOW_DEFINE"
            fi
            if [ -n "$DEFAULT_VALUE_STR" ];then
                OPTIONS[${#OPTIONS[@]}]="$PARAM_SHOW_DEFINE"
            else
                OPTIONALS[${#OPTIONALS[@]}]="$PARAM_SHOW_DEFINE"
            fi
            ARG_NAME='ARGV_'
        else
            SHORT_NAME=''
            NAME=`printf '%s' $PARAM_NAME_STR|grep -oP "^$REGEXP_ARGU"`
            PARAM_SHOW_DEFINE="$NAME"
            ARG_NAME='ARGU_'
        fi
        # 重复参数校验
        for ((INDEX=0; INDEX < ${#ARGVS[@]}; INDEX++)); do
            if test ${ARGVS[$INDEX]} = "$NAME" || test ${ARGVS[$INDEX]} = "$SHORT_NAME";then
                error_exit "不能定义重名参数: ${ARGVS[$INDEX]} , $PARAM"
            fi
        done
        ARGVS[${#ARGVS[@]}]="$NAME"
        if [ -n "$SHORT_NAME" ];then
            ARGVS[${#ARGVS[@]}]="$SHORT_NAME"
        fi
        # 参数默认值写入参数可访问全局变量中
        ARG_NAME=$ARG_NAME`printf '%s' "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
        if [ -n "$DEFAULT_VALUE_STR" ];then
            DEFAULT_VALUE_STR=$(printf '%s' "$DEFAULT_VALUE_STR"|sed -r "s/(^=\s*)//")
            PARAM_SHOW_DEFINE="$PARAM_SHOW_DEFINE [= ${DEFAULT_VALUE_STR:-''}]"
            get_param_string "$DEFAULT_VALUE_STR" $ARG_NAME
        elif ! has_variable $ARG_NAME;then
            eval "$ARG_NAME=''"
        fi
        # 参数有验证写入待验证队列中
        if [ -n "$DEFAULT_VALIDATE_STR" ];then
            VALIDATES_NAME_QUEUE[${#VALIDATES_NAME_QUEUE[@]}]="$ARG_NAME"
            VALIDATES_RULE_QUEUE[${#VALIDATES_RULE_QUEUE[@]}]="$DEFAULT_VALIDATE_STR"
        fi
        # 构造帮助命令中参数展示
        INDEX=$[ $(printf '%s' "$PARAM_SHOW_DEFINE"|wc -m) + 4 ]
        PARAM_SHOW_INFO="    $PARAM_SHOW_DEFINE"
        if ((INDEX >= SPACE_NUM));then
            PARAM_SHOW_INFO="$PARAM_SHOW_INFO\n"
        fi
        PARAM_SHOW_INFO=$PARAM_SHOW_INFO$(printf '%*s' $((INDEX >= SPACE_NUM ? SPACE_NUM : SPACE_NUM-INDEX)))${PARAM:${#PARAM_STR}}
        if [[ "$NAME" == -* ]];then
            COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM_SHOW_INFO \n"
        else
            ARGUMENTS[${#ARGUMENTS[@]}]="$NAME"
            COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM_SHOW_INFO \n"
        fi
    done <<EOF
$(eval "echo -e \"\$$1\"")
[-h, --help]显示脚本使用帮助信息
[-v, --version]显示脚本版本号
EOF
    # 解析匹配传入参数
    local ITEM ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=$(eval echo "\${#$2[@]}")
    for ((ARG_NUM=0; ARG_NUM < ARG_SIZE; ARG_NUM++)); do
        eval ITEM="\${$2[$ARG_NUM]}"
        if [ -z "$ITEM" ];then
            continue
        fi
        NAME=''
        if [[ "$ITEM" =~ ^(--[[:alnum:]][[:alnum:]\-]+(=.*)?|-[[:alnum:]])$ ]]; then
            # 有参数的选项处理
            if [[ "$ITEM" =~ ^--[[:alnum:]][[:alnum:]\-]+=.*$ ]];then
                NAME_TEMP=$(printf '%s' "$ITEM"|grep -oP '^--[[:alnum:]][\w\-]+')
                VALUE=$(printf '%s' "$ITEM"|sed -r "s/^[^=]+=//")
            else
                NAME_TEMP="$ITEM"
                VALUE=''
                for ((INDEX=0; INDEX < ${#OPTIONALS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONALS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=${OPTIONS_TEMP#*--}
                        VALUE='1'
                        break
                    fi
                done
            fi
            if [ -z "$NAME" ];then
                for ((INDEX=0; INDEX < ${#OPTIONS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=${OPTIONS_TEMP#*--}
                        if [[ -z "$VALUE" && "$NAME_TEMP" =~ ^-[A-Za-z0-9]$ ]];then
                            ((ARG_NUM++))
                            eval "VALUE=\${$2[$ARG_NUM]}"
                        fi
                        if [ -z "$VALUE" ] && ! [[ $ITEM =~ = ]] && (($ARG_NUM >= $ARG_SIZE));then
                            error_exit "$NAME 必需指定一个值"
                        fi
                        break
                    fi
                done
            fi
            ARGUMENTS_INDEX=${#ARGUMENTS[@]}
            ARG_NAME='ARGV_'
        elif ((${#ARGUMENTS[@]} > 0 && $ARGUMENTS_INDEX < ${#ARGUMENTS[@]})); then
            NAME=${ARGUMENTS[$ARGUMENTS_INDEX]}
            VALUE="$ITEM"
            ARG_NAME='ARGU_'
            ((ARGUMENTS_INDEX+=1))
        fi
        if [ -z "$NAME" ];then
            warn_msg "未知参数: "$ITEM
        else
            eval "$ARG_NAME${NAME//-/_}=\$VALUE"
        fi
    done
    if [ "$ARGV_help" = '1' ];then
        # 帮助命令强制进入并终止后续执行
        local PARAMS_NAME=() INFO_SHOW_STR=""
        if [ -n "$COMMENT_SHOW_ARGUMENTS" ];then
            PARAMS_NAME[${#PARAMS_NAME[@]}]='[Arguments]'
            INFO_SHOW_STR="Arguments: \n$COMMENT_SHOW_ARGUMENTS\n";
        fi
        if [ -n "$COMMENT_SHOW_OPTIONS" ];then
            PARAMS_NAME[${#PARAMS_NAME[@]}]='[Options]'
            INFO_SHOW_STR=$INFO_SHOW_STR"Options: \n$COMMENT_SHOW_OPTIONS\n";
        fi
        if [ -n "$SHELL_RUN_HELP" ];then
            INFO_SHOW_STR=$INFO_SHOW_STR"Help: \n"$(echo -e "$SHELL_RUN_HELP"|sed -r 's/^(\s*\S)/    \1/g');
        fi
        local RUN_SHOW_STR="    bash $(echo -n "$0"|sed "s,^`pwd`/,,") ${PARAMS_NAME[@]}\n"
        if [ $(basename $0) != 'run.sh' -a -e $SHELL_WROK_BASH_PATH/run.sh ];then
            RUN_SHOW_STR="$RUN_SHOW_STR\n    bash "$(echo -n "$SHELL_WROK_BASH_PATH/"|sed "s,^`pwd`/,,")"run.sh $(basename $0 '.sh') ${PARAMS_NAME[@]}\n"
        fi
        echo -e "Description:
$(echo -e "$SHELL_RUN_DESCRIPTION"|sed -r 's/^(\s*\S)/    \1/g')

Usage:
$RUN_SHOW_STR

$INFO_SHOW_STR";
        exit
    elif [ "$ARGV_version" = '1' ];then
        # 展示脚本版本号信息强制终止后续执行
        echo -e "linux服务器常用工具和安装shell脚本，当前版本号：$SHELL_RUN_VERSION
脚本存放在github上，地址：https://github.com/ttlxihuan/shell"
    else
        # 验证参数
        for ((INDEX=0; INDEX < ${#VALIDATES_NAME_QUEUE[@]}; INDEX++)); do
            validate_shell_param ${VALIDATES_NAME_QUEUE[$INDEX]} "${VALIDATES_RULE_QUEUE[$INDEX]}"
        done
        return 0
    fi
    exit 0
}
# 验证脚本参数
# @command validate_shell_param $name $rules
# @param $name              参数变量全名
# @param $rules             参数规则要求，多个使用|分开
#                           支持规则有：
#                               required                                必填项
#                               required_with:name[,name...]            指定变量有存在时必填，name是参数变量名
#                               required_with_all:name[,name...]        指定变量全部存在时必填，name是参数变量名
#                               required_without:name[,name...]         指定变量有不存在时必填，name是参数变量名
#                               required_without_all:name[,name...]     指定变量全部不存在时必填，name是参数变量名
#                               int[:[min],[max]]       必需是整数，可以指定数值大小范围
#                               float[:[min],[max]]     必需是浮点数，可以指定数值大小范围
#                               string[:[min],[max]]    必需是字符串，可以指定长度范围
#                               ip[:4|6]           必需是ip4或ip6地址，可以指定限定ip4或ip6
#                               url                必需是有效URL
#                               path               必需是存在的目录
#                               file               必需是存在的文件
#                               size               必需是空间大小：百分数（比如：10%）、字节数（比如：20M）
#                               in:opt1,opt2,...   限制可选值
#                               regexp:expr        正则表达式验证，正则使用 [[]] 命令处理
#                           规则名要求：必需是支持的规则名
#                           规则值要求：可以是单或双引号或无引号（特殊字符需要使用转义字符，非特殊字符有：字母、数字、下划线、减号）
# return 1|0
validate_shell_param(){
    local RULE_TEXT RULE_NAME RULE_VALUES ARG_NAME ARG_VALUE LISTS_STR INDEX ARG_REQUIRED_OPT ARG_REQUIRED_VAL VALUE_RULES="($REGEXP_QUOTE_STRING)"
    get_shell_option "$1" ARG_NAME ARG_VALUE
    while read RULE_TEXT; do
        RULE_NAME=$(printf '%s' "$RULE_TEXT"|grep -oP '^[^:\|]+')
        ([[ -z "$ARG_VALUE" && "$RULE_NAME" != required* ]] || [[ -n "$ARG_VALUE" && "$RULE_NAME" == required* ]]) && continue
        RULE_VALUES=($(printf '%s' "${RULE_TEXT:${#RULE_NAME}+1}"|grep -oP "$VALUE_RULES"))
        # 剥离值前后引号
        for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX+=2));do
            get_param_string "${RULE_VALUES[$INDEX]}" RULE_VALUES[$INDEX]
        done
        [[ ! "$RULE_NAME" =~ ^(int|float|string)$ || "${RULE_VALUES[0]}" =~ ^(-?[1-9][0-9]*|[0-9])*$ && "${RULE_VALUES[2]}" =~ ^(-?[1-9][0-9]*|[0-9])*$ ]] ||
            error_exit "脚本参数 ${ARG_NAME} 校验规则错误，选项必需是数值范围：${RULE_TEXT}"
        LISTS_STR=''
        case "$RULE_NAME" in
            int)
                [[ "$ARG_VALUE" =~ ^[\-\+]?([1-9][0-9]*|[0-9])$ ]] || error_exit "脚本参数 ${ARG_NAME} 必需是整数，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" ] || (( ARG_VALUE >= ${RULE_VALUES[0]} )) || error_exit "脚本参数 ${ARG_NAME} 必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[1]}" ] || (( ARG_VALUE <= ${RULE_VALUES[1]} )) || error_exit "脚本参数 ${ARG_NAME} 必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            float)
                tools_install bc
                [[ "$ARG_VALUE" =~ ^-?([1-9][0-9]*|[0-9])(\.[0-9]+)?$ ]] || error_exit "脚本参数 ${ARG_NAME} 必需是浮点数，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" -o $(echo "$ARG_VALUE >= ${RULE_VALUES[0]}"|bc) = '1' ] || error_exit "脚本参数 ${ARG_NAME} 必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[0]}" -o $(echo "$ARG_VALUE <= ${RULE_VALUES[1]}"|bc) = '1' ] || error_exit "脚本参数 ${ARG_NAME} 必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            string)
                [ -z "${RULE_VALUES[0]}" ] || (( ${#ARG_VALUE} >= ${RULE_VALUES[0]} )) || error_exit "脚本参数 ${ARG_NAME} 字符长度必需 >= ${RULE_VALUES[0]}，当前是：$ARG_VALUE"
                [ -z "${RULE_VALUES[1]}" ] || (( ${#ARG_VALUE} <= ${RULE_VALUES[1]} )) || error_exit "脚本参数 ${ARG_NAME} 字符长度必需 <= ${RULE_VALUES[1]}，当前是：$ARG_VALUE"
            ;;
            path)
                [[ "$ARG_VALUE" =~ ^[~/] && -d "$ARG_VALUE" ]] || [[ "$ARG_VALUE" =~ ^[^~/] && -d "$SHELL_WROK_BASH_PATH/$ARG_VALUE" ]] ||
                error_exit "脚本参数 ${ARG_NAME} 指定目录不存在，当前是：$ARG_VALUE"
            ;;
            file)
                [[ "$ARG_VALUE" =~ ^[~/] && -e "$ARG_VALUE" ]] || [[ "$ARG_VALUE" =~ ^[^~/] && -e "$SHELL_WROK_BASH_PATH/$ARG_VALUE" ]] ||
                error_exit "脚本参数 ${ARG_NAME} 指定文件不存在，当前是：$ARG_VALUE"
            ;;
            size)
                [[ "$ARG_VALUE" =~ ^([0-9]|[1-9][0-9]*)[BKMG%]?$ ]] || error_exit "脚本参数 ${ARG_NAME} 必需指定空间大小，比如：10% 或 10M，当前是：$ARG_VALUE"
            ;;
            required)
                error_exit "脚本参数 ${ARG_NAME} 不可为空"
            ;;
            required_with)
                for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -z "$ARG_REQUIRED_VAL" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} 指定后不可为空"
                done
            ;;
            required_with_all)
                for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -z "$ARG_REQUIRED_VAL" ] && continue 2
                    LISTS_STR="$LISTS_STR, $ARG_REQUIRED_OPT"
                done
                error_exit "脚本参数 ${ARG_NAME} 在 ${LISTS_STR:2} 指定后不可为空"
            ;;
            required_without)
                for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -n "$ARG_REQUIRED_VAL" ] || error_exit "脚本参数 ${ARG_NAME} 在 ${ARG_REQUIRED_OPT} 不指定时不可为空"
                done
            ;;
            required_without_all)
                for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    get_shell_option "${RULE_VALUES[$INDEX]}" ARG_REQUIRED_OPT ARG_REQUIRED_VAL
                    [ -n "$ARG_REQUIRED_VAL" ] && continue 2
                    LISTS_STR="$LISTS_STR, $ARG_REQUIRED_OPT"
                done
                error_exit "脚本参数 ${ARG_NAME} 在 ${LISTS_STR:2} 不指定时不可为空"
            ;;
            ip)
                [[ -z "${RULE_VALUES[0]}" || "${RULE_VALUES[0]}" =~ ^[46]$ ]] || error_exit "脚本参数 ${ARG_NAME} 校验规则错误，选项必需4或6：${RULE_TEXT}"
                [[ "${RULE_VALUES[0]}" =~ ^4?$ && "$ARG_VALUE" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || 
                [[ "${RULE_VALUES[0]}" =~ ^6?$ && "$ARG_VALUE" =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){7}$ ]] ||
                error_exit "脚本参数 ${ARG_NAME} 不是有效ip${RULE_VALUES[0]:-4/6}地址，当前是：$ARG_VALUE"
            ;;
            url)
                printf '%s' "$ARG_VALUE"|grep -qP '^http(s)?://\w+(\.\w+)*(/.*)?' || error_exit "脚本参数 ${ARG_NAME} 不是有效url地址，当前是：$ARG_VALUE"
            ;;
            in)
                for ((INDEX=0;INDEX<${#RULE_VALUES[@]};INDEX++));do
                    if [ "${RULE_VALUES[$INDEX]}" = "$ARG_VALUE" ];then
                        ARG_EXIST=1
                        continue 2
                    fi
                    LISTS_STR="$LISTS_STR, ${RULE_VALUES[$INDEX]}"
                done
                error_exit "脚本参数 ${ARG_NAME} 必需是可选值其一：${LISTS_STR:2}，当前是：$ARG_VALUE"
            ;;
            regexp)
                [ -z "${RULE_VALUES[0]}" ] || eval [[ "\${ARG_VALUE}" =~ ${RULE_VALUES[0]} ]] || error_exit "脚本参数 ${ARG_NAME} 不符合正则表达式：${RULE_VALUES[0]}，当前是：$ARG_VALUE"
            ;;
            *)
                warn_msg "脚本参数 ${ARG_NAME} 无处理验证：$RULE_NAME"
            ;;
        esac
    done <<EOF
$(printf '%s' "$2"|grep -oP "[^:\|]+(:$VALUE_RULES(,$VALUE_RULES)*)?\|?")
EOF
}
# 获取参数定义的字符串，处理会剥离前后引号，转义内部字符并写入指定变量中
# @command get_param_string $string $set_value
# @param $string            要处理字符串
# @param $set_value         写入变量名
# return 1|0
get_param_string(){
    local _TEMP_STRING=$(printf '%s' "$1"|sed -r "s/(^['\"])|(['\"]$)//g")
    stripc_slashes _TEMP_STRING
    eval $2="\$_TEMP_STRING"
}
# 去掉转义
# @command stripc_slashes $string_name [...]
# @param $string_name       要添加的字符串变量名
# return 1|0
stripc_slashes(){
    local VAL_NAME
    for VAL_NAME in $@;do
        eval $VAL_NAME="\$(echo -n -e \"\${$VAL_NAME}\")"
    done
}
# 通过变量名获取shell脚本选项信息（解析匹配脚本全局参数）
# @command get_shell_option $name $set_opt $set_val
# @param $name              要解析变量名
# @param $set_opt           解析选项成功写入变量名
# @param $set_val           解析选项值成功写入变量名
# return 1|0
get_shell_option(){
    local SHELL_OPTION_PREFIX='' SHELL_OPTION_NAME="${1:5}"
    if [[ "$1" == ARGV_* ]];then
        SHELL_OPTION_PREFIX='--'
    elif [[ "$1" != ARGU_* ]];then
        error_exit "${1} 未知校验参数"
    fi
    eval $2="$SHELL_OPTION_PREFIX${SHELL_OPTION_NAME//_/-}"
    eval $3=\${$1}
}
# 工具集安装
# @command tools_install $tool1 [$tool2 ...]
# @param $tool1 ...     工具名集（工具名全部是通用的）
# return 0
tools_install(){
    local TOOL
    for TOOL in $*; do
        if ! if_command $TOOL;then
            package_manager_run install $TOOL 2> /dev/null
            if ! if_command $TOOL;then
                error_exit "安装工具 $TOOL 失败"
            fi
        fi
    done
    return 0
}
# 包管理系统运行
# @command package_manager_run $command $package_name
# @param $command       执行的命令
# @param $package_name   操作的包名，或变量名，变量名前面需要增加 - 如 package_manager_run install -PACKAGE_NAME
# return 1|0
package_manager_run(){
    local COMMAND_STR
    case $1 in
        install)
            COMMAND_STR=${PACKAGE_MANAGER_INSTALL_COMMAND[$PACKAGE_MANAGER_INDEX]}
        ;;
        update)
            COMMAND_STR=${PACKAGE_MANAGER_UPDATE_COMMAND[$PACKAGE_MANAGER_INDEX]}
        ;;
        remove)
            COMMAND_STR=${PACKAGE_MANAGER_REMOVE_COMMAND[$PACKAGE_MANAGER_INDEX]}
        ;;
        info)
            COMMAND_STR=${PACKAGE_MANAGER_INFO_COMMAND[$PACKAGE_MANAGER_INDEX]}
        ;;
        *)
            error_exit "未知包管理命令: $1"
        ;;
    esac
    if [ -z "$2" ];then
        error_exit "最少指定一个要安装的包名"
    fi
    local NAME COMMAND_ARRAY_VAL PACKAGE_NAME COMMAND_ARRAY
    for NAME in ${@:2}; do
        if [ ${NAME:0:1} = '-' ];then
            eval COMMAND_ARRAY="\${#${NAME:1}[@]}"
            if [ "$COMMAND_ARRAY" -gt 1 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'['$[PACKAGE_MANAGER_INDEX]']}'
            elif [ "$COMMAND_ARRAY" -gt 0 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'[0]}'
            else
                error_exit "找不到配置的安装包名: $NAME"
            fi
            eval PACKAGE_NAME="$COMMAND_ARRAY_VAL"
            if [ "$PACKAGE_NAME" = '-' -o "$PACKAGE_NAME" = '' ];then
                continue;
            fi
        else
            PACKAGE_NAME=$NAME
        fi
        if [ -z "$PACKAGE_NAME" ];then
            error_exit "安装包名解析为空: $NAME"
        fi
        run_msg "$COMMAND_STR $PACKAGE_NAME" 2>/dev/null
        if [ $? != '0' ];then
            warn_msg "$COMMAND_STR $PACKAGE_NAME 运行失败，可能会影响后续运行结果"
        fi
    done
}
# 获取包管理对应包最新版本号
# @command get_package_version $package_name $set_val
# @param $package_name  操作的包名，或变量名，变量名前面需要增加
# @param $set_val       版本号写入变量名，能获取版本号才写入
# return 1|0
get_package_version(){
    local VERSION=$(package_manager_run info "$1"|grep -iP '^version\s*:'|grep -oP '\d+(\.\d+)+'|head -n 1)
    if [ -n "$VERSION" ];then
        eval $2=\$VERSION
        return 0
    else
        return 1
    fi
}
# 获取包管理后缀
# @command package_manager_suffix $set_val
# @param $set_val       后缀写入变量名
# return 1|0
package_manager_suffix(){
    if [ -z "${PACKAGE_MANAGER_FILE_SUFFIX[$PACKAGE_MANAGER_INDEX]}" ];then
        error_exit "该系统包管理后缀名暂未支持"
    fi
    eval "$1=\${PACKAGE_MANAGER_FILE_SUFFIX[$PACKAGE_MANAGER_INDEX]}"
}
# 判断系统适用哪个包管理器
if if_command yum;then
    PACKAGE_MANAGER_INDEX=0
    # epel-release 第三方软件依赖库EPEL，给yum、rpm等工具使用
    #yum -y install epel-release
    # 创建元数据缓存
    #yum makecache 2>&1 &>/dev/null
    yum -y update nss 2>&1 &>/dev/null &
elif if_command apt;then
    PACKAGE_MANAGER_INDEX=1
elif if_command dnf;then
    PACKAGE_MANAGER_INDEX=2
elif if_command pkg;then
    PACKAGE_MANAGER_INDEX=3
else
    error_exit '暂无支持包管理，请确认系统信息，目前只支持：yum、apt'
fi
# 提取工作目录
SHELL_WROK_BASH_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../"; pwd)"
safe_realpath SHELL_WROK_BASH_PATH
SHELL_WROK_INCLUDES_PATH="${SHELL_WROK_BASH_PATH}/includes"
SHELL_WROK_INSTALLS_PATH="${SHELL_WROK_BASH_PATH}/installs"
SHELL_WROK_TOOLS_PATH="${SHELL_WROK_BASH_PATH}/tools"
SHELL_WROK_ISOLATES_PATH="${SHELL_WROK_BASH_PATH}/isolates"
SHELL_WROK_HELPERS_PATH="${SHELL_WROK_BASH_PATH}/helpers"
SHELL_WROK_TEMP_PATH="${SHELL_WROK_BASH_PATH}/temp"
SHELL_WROK_ETC_PATH="${SHELL_WROK_BASH_PATH}/etc"
REGEXP_QUOTE_STRING="([\w\-]+|\\\\.)+|\"([^\"]+|\\\\.)*\"|'([^']+|\\\\.)*'"
mkdirs "$SHELL_WROK_TEMP_PATH"
# 获取总线程数
TOTAL_THREAD_NUM=$(lscpu |grep '^CPU(s)'|grep -oP '\d+$')
# 初始化脚本处理
if has_function init_shell;then
    init_shell
fi
# 包配置
source "$SHELL_WROK_INCLUDES_PATH/config.sh" || exit
# 提取参数
source "$SHELL_WROK_INCLUDES_PATH/argvs.sh" || exit
# 解析参数
parse_shell_param DEFINE_RUN_PARAMS CALL_INPUT_ARGVS

# 常规高精度公式计算
# @command math_compute $result $formula [$scale]
# @param $result            计算结果写入变量名
# @param $formula           计算公式
# @param $scale             计算小数精度位数，默认是0
#                           支持运算：+-*/^%
# return 1|0
math_compute(){
    tools_install bc
    local SCALE_NUM=0
    if [ -n "$3" ]; then
        SCALE_NUM=$(printf '%s' "$3"|grep -oP '^\d+'|awk '{if($1 == ""){print "0"}else{print $1}}')
    fi
    RESULT_STR=`echo "scale=$SCALE_NUM; $2"|bc|sed 's/\\\\//'|awk -F '.' '{if($1 ~ "[+-]" || $1==""){print "0."$2}else{print $1"."$2}}'|sed 's/ //g'|grep -oP "^\d+(\.\d{0,$SCALE_NUM})?"|grep -oP '^\d+(\.\d*[1-9])?'`
    eval "$1='$RESULT_STR'"
}
# 大小单位转换
# @command size_format $var_name $size [$to_unit] [$scale]
# @param $var_name              格式化写入变量名
# @param $size                  容量值，无单位以B为准，支持单位：B、K、M、G、T等
# @param $to_unit               转到目标单位，默认是B为单位
# @param $scale                 计算小数精度位数，默认是 2
# return 1|0
size_switch(){
    local UNIT_POWER UNIT_BASE=1024 UNIT_SWITCH=("$2" "${3:-B}") UNIT_SWITCH_UNIT=() INDEX
    for ((INDEX=0;INDEX<=1;INDEX++));do
        case "${UNIT_SWITCH[$INDEX]}" in
            *E|*EB)
                UNIT_SWITCH_UNIT[$INDEX]=6
                ;;
            *P|*PB)
                UNIT_SWITCH_UNIT[$INDEX]=5
                ;;
            *T|*TB)
                UNIT_SWITCH_UNIT[$INDEX]=4
                ;;
            *G|*GB)
                UNIT_SWITCH_UNIT[$INDEX]=3
                ;;
            *M|*MB)
                UNIT_SWITCH_UNIT[$INDEX]=2
                ;;
            *K|*KB)
                UNIT_SWITCH_UNIT[$INDEX]=1
                ;;
            *B)
                UNIT_SWITCH_UNIT[$INDEX]=0
                ;;
            *[^A-Z])
                UNIT_SWITCH_UNIT[$INDEX]=0
                ;;
            *)
                error_exit "未知存储容量单位：${UNIT_SWITCH[$INDEX]}"
                ;;
        esac
    done
    if (( ${UNIT_SWITCH_UNIT[0]} >= ${UNIT_SWITCH_UNIT[1]} ));then
        math_compute $1 "${2//[^0-9\.]/} * ($UNIT_BASE ^ (${UNIT_SWITCH_UNIT[0]} - ${UNIT_SWITCH_UNIT[1]}))" ${4:-2}
    else
        math_compute $1 "${2//[^0-9\.]/} / ($UNIT_BASE ^ (${UNIT_SWITCH_UNIT[1]} - ${UNIT_SWITCH_UNIT[0]}))" ${4:-2}
    fi
}
# 大小格式化到适合单位
# @command size_format $var_name $size
# @param $var_name              格式化写入变量名
# @param $size                  容量值，无单位以B为准，支持单位：B、K、M、G、T等
# return 1|0
size_format(){
    local UNIT_POWER=0 CURRENT_SIZE=$2 UNIX_NAMES=('B' 'K' 'M' 'G' 'T' 'P' 'E') VALUE_SIZE
    while ((CURRENT_SIZE >= 1024)); do
        ((CURRENT_SIZE=CURRENT_SIZE/1024))
        ((UNIT_POWER++))
    done
    if [ -z "${UNIX_NAMES[$UNIT_POWER]}" ];then
        error_exit "未知存储容量大小：${2}"
    fi
    math_compute VALUE_SIZE "${2} / (1024 ^ $UNIT_POWER)" 2
    eval "$1=$VALUE_SIZE${UNIX_NAMES[$UNIT_POWER]}"
}
# 获取系统名及版本号
# 获取系统版本信息的命令很多
#   cat /proc/version
#   cat /etc/os-release
#   cat /etc/issue
#   uname -a
# @command get_os
# return 1|0
get_os(){
    if [ -e '/etc/os-release' ];then
        echo $(source /etc/os-release;echo "$ID $VERSION_ID"|tr '[:upper:]' '[:lower:]')
    elif [ -e '/etc/issue' ];then
        cat /etc/issue|grep -oP '\w+\s+(release\s+)?\d+\.\d'|sed -r 's/release\s+//'|tr '[:upper:]' '[:lower:]'
    fi
}
# 获取当前IP地址，内网是局域IP，写入全局变量SERVER_IP
# @command get_ip
# return 1|0
get_ip(){
    SERVER_IP='127.0.0.1'
    if ! if_command ifconfig;then
        package_manager_run install net-tools
    fi
    if if_command ifconfig;then
        SERVER_IP=`ifconfig|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o -m 1|head -n 1`
    else
        warn_msg '没有ifconfig命令，无法获取当前IP，将使用默认地址：'$SERVER_IP
    fi
}
# 判断防火墙是否
# 默认没有iptables.service服务可以自己安装
# yum install iptables-services
# @command has_iptables_run
# return 1|0
has_iptables_run(){
    #判断是否开启了服务
    if if_command ufw;then
        # ubuntu 系统专用
        ufw status 2>/dev/null|grep -q 'inactive'
    elif if_command firewalld;then
        # 高版本系统默认
        systemctl status firewalld 2>/dev/null|grep -q 'Active: inactive (dead)'
    elif if_command systemctl;then
        systemctl status iptables 2>/dev/null|grep -q 'Active: inactive (dead)'
    else
        service iptables status 2>/dev/null|grep -q 'not running'
    fi
    [ $? != '0' ];
}
# 获取文件系统的信息
# 此命令主要是处理很长的存储名可能会换行导致awk处理错位
# 虚拟机常见，通过修正可以让存储名与对应的信息保持在一行中
# @command df_awk $options
# @param $options         选项参数
# return 1|0
df_awk(){
    #去掉首行标题，合并截断行
    df $@|awk '{if(NR > 1){if(NF==1){prev=$1}else{{print prev,$1,$2,$3,$4,$5,$6,$7}prev=""}}}'
}
# 解析列表并去重再导出数组
# @command parse_lists $export_name $string $separator $match
# @param $export_name       计算结果写入变量名
# @param $string            要解析的列表字符串
# @param $separator         列表字符串的分隔符，可以是正则
# @param $match             列表每项匹配正则
# return 1|0
parse_lists(){
    local ITEM NEXT INDEX PARSE_STRING=`printf '%s' "$2"|sed -r "s/(^\s+|\s+$)//g"` PARSE_ARRAY=()
    eval "$1=()"
    while [ -n "$PARSE_STRING" ]; do
        NEXT=$(printf '%s' "$PARSE_STRING"|grep -oP "^.*?$3")
        ITEM=$(printf '%s' "$NEXT"|sed -r "s/(^\s+|\s*$3$)//g")
        if [ -z "$ITEM" ];then
            NEXT="$PARSE_STRING"
            ITEM="$PARSE_STRING"
        fi
        if printf '%s' "$ITEM"|grep -qP "^$4$";then
            PARSE_STRING=${PARSE_STRING:$(printf '%s' "$NEXT"|wc -m)}
            # 去重处理
            if search_array "$ITEM" "$1";then
                continue
            fi
            eval "$1[\${#$1[@]}]"="\$ITEM"
        else
            warn_msg "集合拆分未识别内容： $ITEM"
        fi
    done
    return 0
}
# 搜索指定元素在数据中的第一个匹配位置
# @command search_array $value $array_name [$val_name] [$start_index]
# @param $value             要搜索的元素值
# @param $array_name        要搜索的数组变量名
# @param $val_name          搜索到位置写入变量名，没找到为-1
# @param $start_index       指定搜索开始位置，默认为0
# return 1|0
search_array(){
    local INDEX=${4:-0} SIZE=$(eval "echo \${#$2[@]}")
    for ((;INDEX < SIZE;INDEX++));do
        if [ "$1" = $(eval "echo \${$2[$INDEX]}") ];then
            if [ -n "$3" ];then
                eval "$3=$INDEX"
            fi
            return 0
        fi
    done
    if [ -n "$3" ];then
        eval "$3=-1"
    fi
    return 1
}
# 是否正在运行指定脚本
# @command has_run_shell $name $options
# @param $name              脚本名，可使用正则，不包含 .sh 后缀
# @param $options           脚本运行必需参数规则，可使用正则
# return 1|0
has_run_shell(){
    local RUN_EXE RUN_PARAMS="$2"
    if [ -z "$RUN_PARAMS" ];then
        if [[ "$1" == *-install ]];then
            RUN_PARAMS="\s+(new|\d+(\.\d+)+)"
        else
            RUN_PARAMS="([\s&>;]+|$)"
        fi
    fi
    while read RUN_EXE;do
        if [ -n "$RUN_EXE" -a -e "$RUN_EXE" ] && readlink $RUN_EXE 2>/dev/null|grep -qP "(/bash|/sh|${BASH})$";then
            return 0
        fi
    done <<EOF
$(ps aux|grep -P "(bash|sh|source|${BASH})\s+(.*/)?$1\.sh$RUN_PARAMS"|awk '{if($2 != '$$'){print "/proc/"$2"/exe"}}')
EOF
    return 1
}
# 运行指定内置脚本
# @command find_project_file $name [$options ...]
# @param $name              脚本名称，不需要后缀
# @param $var_noptionsame   脚本运行参数
# return 1|0
run_shell(){
    local RUN_SHELL_PATH=$(cd "$SHELL_WROK_BASH_PATH";find ./installs ./tools -name "$1.sh") 
    if [ -z "$RUN_SHELL_PATH" ];then
        error_exit "不存在 $1 内置脚本"
    fi
    safe_realpath RUN_SHELL_PATH
    shift
    source "$SHELL_WROK_INCLUDES_PATH/argvs.sh" || exit
    run_msg bash $RUN_SHELL_PATH ${CALL_SAFE_ARGVS[@]}
    if_error "脚本运行失败： $RUN_SHELL_PATH"
}
# 运行安装脚本
# @command run_install_shell $name $version_num [$other ...]
# @param $name              安装脚本名，比如：gcc
# @param $version_num       安装版本号
# @param $other             其它安装参数集
# return 1|0
run_install_shell(){
    local INSTALL_NAME="$1-install"
    shift
    source "$SHELL_WROK_INCLUDES_PATH/argvs.sh" || exit
    eval run_shell "$INSTALL_NAME" ${CALL_SAFE_ARGVS[@]} --disk-space=${ARGV_disk_space} --memory-space=${ARGV_memory_space} --install-path=${INSTALL_BASE_PATH}
    source /etc/profile
}
# 搜索项目中对应文件
# @command find_project_file $type $name $var_name
# @param $type              搜索类型
# @param $name              搜索名称，不需要后缀
# @param $var_name          搜索成功后写入变量
# return 1|0
find_project_file(){
    local FIND_DIR FIND_NAME
    case $1 in
        include)
            FIND_DIR=$SHELL_WROK_INCLUDES_PATH
            FIND_NAME="$2.sh"
        ;;
        install)
            FIND_DIR=$SHELL_WROK_INSTALLS_PATH
            FIND_NAME="$2-install.sh"
        ;;
        tool)
            FIND_DIR=$SHELL_WROK_TOOLS_PATH
            FIND_NAME="$2.sh"
        ;;
        etc)
            FIND_DIR=$SHELL_WROK_ETC_PATH
            FIND_NAME="$2.conf"
        ;;
        *)
            error_exit "可搜索类型错误 $1"
        ;;
    esac
    local FIND_LISTS=($(find "$FIND_DIR" -name "$FIND_NAME"))
    if [ ${#FIND_LISTS[@]} = '0' ];then
        error_exit "在 $FIND_DIR 目录下搜索不到 $2"
    elif [ ${#FIND_LISTS[@]} = '1' ];then
        eval $3=$(cd "$(dirname "${FIND_LISTS[0]}")";pwd)/$(basename "${FIND_LISTS[0]}")
    else
        error_exit "在 $FIND_DIR 目录下搜索到 ${#FIND_LISTS[@]} 个匹配项"
    fi
}
# 修改配置参数
# @command edit_conf $file $match_regexp $new_set
# @param $file              要修改的配置文件
# @param $match_regexp      匹配修改项，注意有反向引用需要增加小括号，匹配会自动增加^$首尾限制
# @param $new_set           解析选项值成功写入变量名，如果配置项不存在时直接写入内容
# return 1|0
edit_conf(){
    local SET_LINE
    if [ -e "$1" ];then
        SET_LINE=$(grep -m 1 -noP "^${2}$" $1|grep -oP '^\d+')
    else
        warn_msg "配置文件 $1 不存在，已自动创建"
    fi
    if [ -n "$SET_LINE" ];then
        sed -i "${SET_LINE}c${3}" $1
    else
        echo "${3}" >> $1
    fi
}

# 基本处理
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
if [ "$(whoami)" != 'root' ];then
    warn_msg '当前执行用户非 root 可能会影响脚本正常运行！'
fi
