#!/bin/bash
# 切换工作目录
# @command chdir $path
# @param $path      切换的子目录
# return 1|0
chdir(){
    mkdirs $CURRENT_PATH/$1
    cd $CURRENT_PATH/$1
}
# 递归创建目录
# @command mkdirs $path [$user]
# @param $path      创建的目录
# @param $user      指定目录所有者用户
# return 1|0
mkdirs(){
    if [ ! -d "$1" ];then
        mkdir -p "$1"
        if_error "mkdir fail: $1"
    fi
    if [ -n "$2" ];then
        chown -R $2:$2 "$1"
    fi
    return 0
}
# 添加动态库
# @command add_pkg_config $path
# @param $path      动态库目录
# return 1|0
add_pkg_config(){
    # 设置了环境变量
    local PATH_INFO=`find $1/lib* -name '*.pc'|head -n 1` PKG_FILENAME
    if [ -n "$PATH_INFO" ];then
        PKG_FILENAME=${PATH_INFO#*/}
        PKG_FILENAME=${PKG_FILENAME%/.pc}
        if ! if_lib "$PKG_FILENAME"; then
            add_path ${PATH_INFO%/*} PKG_CONFIG_PATH
            return 0;
        fi
    fi
    return 1;
}
# 判断版本大小
# @command if_version $version1 $if $version2
# @param $version1  版本号1
# @param $if        判断条件：>=,>,<=,<,==,!=
# @param $version2  版本号2
# return 1|0
if_version(){
    local VERSIONS=`echo -e "$1\n$3"|sort -Vrb` RESULT
    case "$2" in
        "==")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 1`
        ;;
        "!=")
            RESULT=`echo -e "$VERSIONS"|uniq|wc -l|grep 2`
        ;;
        ">")
            RESULT=`echo -e "$VERSIONS"|uniq -u|head -n 1|grep "$1"`
        ;;
        ">=")
            RESULT=`echo -e "$VERSIONS"|uniq|head -n 1|grep "$1"`
        ;;
        "<")
            RESULT=`echo -e "$VERSIONS"|uniq -u|tail -n 1|grep "$1"`
        ;;
        "<=")
            RESULT=`echo -e "$VERSIONS"|uniq|tail -n 1|grep "$1"`
        ;;
        *)
            error_exit "if_version unknown $2"
        ;;
    esac
    if [ -n "$RESULT" ]; then
        return 0;
    fi
    return 1;
}
# 获取版本
# @command get_version $var_nam $url $version_path_rule [$version_rule]
# @param $var_nam           获取版本号变量名
# @param $url               获取版本号的HTML页面地址
# @param $version_path_rule 匹配版本号的正则规则（粗级匹配，获取所有版本号再排序提取最大的）
# @param $version_rule      提取版本号的正则规则（精准匹配，直接对应的版本号）
# return 1|0
get_version(){
    local VERSION_RULE="$4" VERSION
    if [ -z "$4" ];then
        VERSION_RULE='\d+\.\d+(\.\d+)?'
    fi
    VERSION=`curl $2 -LkN 2>/dev/null| grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
    if [ -z "$VERSION" ];then
        error_exit "get_version fail: $2"
    fi
    eval "$1=\"$VERSION\""
    return 0
}
# 下载软件
# @command download_software $url [$to_path]
# @param $url       下载包的绝对URL地址
# @param $to_path   下载后解压的目录,默认以版本号结构
# return 1|0
download_software(){
    local FILE_NAME=`echo "$1"|grep -oP "[^/]+$"` DIR_NAME TAR_FILE_NAME
    if [ -z "$2" ];then
        DIR_NAME=`echo "$FILE_NAME"|grep -oP "^[\w\-]+(:?\d+(\.\d+)*)"`
    else
        DIR_NAME="$2"
    fi
    if [ -z "$DIR_NAME" ];then
        error_exit "work dir empty"
    fi
    chdir $INSTALL_NAME
    # 重新下载再安装
    if [ -n "$ARGV_reset" -a "$ARGV_reset" = '2' ];then
        if [ -e "$FILE_NAME" ];then
            rm -f $FILE_NAME
        fi
        if [ -d "$DIR_NAME" ];then
            rm -rf $DIR_NAME
        fi
    fi
    if [ ! -e "$FILE_NAME" ];then
        if ! wget --no-check-certificate -T 7200 $1; then
            curl -OLkN --connect-timeout 7200 $1
        fi
        if [ $? -ne 0 ];then
            mv $FILE_NAME "`date +'%Y_%m_%d_%H_%M_%S'`_error_$FILE_NAME"
            error_exit "download fail: $1"
        fi
    fi
    if [ ! -d "$DIR_NAME" ];then
        case "$FILE_NAME" in
            *.gz|*.tar.gz|*.tgz)
                tar -zxf $FILE_NAME
            ;;
            *.tar|*.tar.bz2)
                tar -xf $FILE_NAME
            ;;
            *.zip)
                if ! if_command unzip; then
                    packge_manager_run install -UNZIP_PACKGE_NAMES
                fi
                unzip $FILE_NAME
            ;;
            *.tar.xz)
                if ! if_command xz; then
                    packge_manager_run install -XZ_PACKGE_NAMES
                fi
                xz -d $FILE_NAME
                TAR_FILE_NAME=${FILE_NAME%*.xz}
                tar -xf $TAR_FILE_NAME
            ;;
            *.rpm|*.pem)
                return 0
            ;;
            *)
                error_exit "unknown decompression file: $FILE_NAME"
            ;;
        esac
        if_error "decompression fail: $FILE_NAME"
        echo "sha256: "`sha256sum $FILE_NAME`
    fi
    cd $DIR_NAME
    if_error "dir not exists: $DIR_NAME"
    return 0
}
# 解析安装命令参数
# @command parse_install_param $define_name [$options_name]
# @param $define_name       外加定义参数变量名
#                           配置参数规则：
#                           [name]              定义参数
#                           [-n, --name]        定义无值选项
#                           [-n, --name='']     带选项值的选项
# @param $options_name      命令参数数组名
# return 1|0
parse_install_param(){
    local _PARSE_DEFINE_PARAMS_STR_ _PARSE_DEFINE_PARAMS_="
[version] 指定安装版本，不传则是获取最新稳定版本号，传new安装最新版，传指定版本号则安装指定版本应用
[-h, --help]显示帮助信息
[-r, --reset=0]重新安装：0 标准安装，1 重新安装 2重新下载再安装，默认0
[-o, --options='']添加编译选项，使用前请查阅下面帮助说明
"
    if [ -n "$1" ];then
        _PARSE_DEFINE_PARAMS_=$_PARSE_DEFINE_PARAMS_$(eval "echo -e \"\$$1\"")
    fi
    parse_command_param _PARSE_DEFINE_PARAMS_ _PARSE_DEFINE_PARAMS_STR_ $2
    if [ -n "$ARGV_help" ];then
        echo -e "
Description:
    安装${INSTALL_NAME}脚本

Usage:
    bash ${INSTALL_NAME}-install.sh [arguments] [options ...]

${_PARSE_DEFINE_PARAMS_STR_}
Help:
    安装脚本一般使用方式:

        获取最新稳定安装版本号:
            bash ${INSTALL_NAME}-install.sh

        安装最新稳定版本${INSTALL_NAME}:
            bash ${INSTALL_NAME}-install.sh new

        安装指定版本${INSTALL_NAME}:
            bash ${INSTALL_NAME}-install.sh 1.1.1

        安装最新稳定版本${INSTALL_NAME}且指定安装选项:
            bash ${INSTALL_NAME}-install.sh new --options=\"?ext1 ext2\"

    添加编译选项：编译选项只针对使用configure或cmake方式安装有效，指定时需要提前了解编译安装的选项作用和依赖。
                    1、不解析选项直接使用 --xx 、-xx 或 ?--xx 、?-xx
                    2、需要启用选项 xx 或 ?xx 解析后是 --enable-xx 或 --with-xx 
                    3、需要禁用选项 !xx 或 ?!xx 解析后是 --disable-xx
                  选项前面的?是在编译选项时会查找选项是否存在，如果不存在则跳过，存在则添加
                  选项前面的!是在编译选项时查询禁用选项是否存在

    注意：安装脚本会在脚本所有目录创建安装临时目录，此目录用于下载安装包，如果有已经下载好的包可以自行存放目录内可以节省下载时间。
";
        exit 0
    fi
}
# 解析命令参数
# 命令参数解析成功后，将写入参数名规则：ARGV_参数全名（横线转换为下划线，缩写选项使用标准选项代替，使用时注意参数名的大小写不变）
# 注意：定义参数解析成功后会输出，如果不需要输出需要作提取处理
# @command parse_command_param $define_name $output_name $options_name
# @param $define_name       定义参数变量名
#                           配置参数规则：
#                           [name]              定义参数
#                           [-n, --name]        定义无值选项
#                           [-n, --name='']     带选项值的选项
# @param $output_name       命令参数解析后导出变量名
# @param $options_name      命令参数数组名
# return 1|0
parse_command_param() {
    local PARAM NAME SHORT_NAME DEFAULT_VALUE DEFAULT_VALUE_STR PARAM_STR PARAM_INFO_STR PARAM_NAME_STR PARAM_SHOW_DEFINE PARAM_SHOW_INFO ARG_NAME INDEX ARGUMENTS=() OPTIONS=() OPTIONALS=() ARGVS=() COMMENT_SHOW_ARGUMENTS='' COMMENT_SHOW_OPTIONS='' PARAMS_SHOW_STR=''
    # 解析定义的参数
    while read -r PARAM; do
        if echo "$PARAM"|grep -qP '^\s*$'; then
            continue;
        fi
        PARAM_STR=$(echo "$PARAM"|grep -oiP "^\s*\[\s*((-[a-z0-9]\s*,\s*)?--[a-z0-9][\w\-]+|[a-z0-9][\w\-]+)(\s*=\s*(\w+|\"([^\"]|\\\\.)*\"|'([^']|\\\\.)*'))?\s*\]\s*")
        if [ -z "$PARAM_STR" ];then
            error_exit " $PARAM"
        fi
        PARAM_INFO_STR=`echo "$PARAM_STR"|sed -r "s/(^\s*\[\s*)|(\s*\]\s*$)//g"`
        PARAM_NAME_STR=`echo "$PARAM_INFO_STR"|grep -oP '^[^=]+'`
        DEFAULT_VALUE_STR=$(echo "$PARAM_INFO_STR"|grep -oP "=\s*(\w+|\"([^\"]|\\\\.)*\"|'([^']|\\\\.)*')$")
        if echo "$PARAM_NAME_STR"|grep -qP '^-{1,2}';then
            SHORT_NAME=`echo "$PARAM_NAME_STR"|grep -oiP '^-[a-z0-9]'`
            NAME=`echo "$PARAM_NAME_STR"|grep -oiP '\-\-[a-z0-9][\w\-]+'`
            PARAM_SHOW_DEFINE="$NAME"
            if [ -n "$SHORT_NAME" ];then
                PARAM_SHOW_DEFINE="$SHORT_NAME, $PARAM_SHOW_DEFINE"
            fi
            if [ -n "$DEFAULT_VALUE_STR" ];then
                OPTIONS[${#OPTIONS[@]}]="$PARAM_SHOW_DEFINE"
            else
                OPTIONALS[${#OPTIONALS[@]}]="$PARAM_SHOW_DEFINE"
            fi
        else
            SHORT_NAME=''
            NAME=`echo $PARAM_NAME_STR|grep -oiP '^[a-z0-9][\w\-]+'`
            PARAM_SHOW_DEFINE="$NAME"
        fi
        for ((INDEX=0; INDEX < ${#ARGVS[@]}; INDEX++)); do
            if test ${ARGVS[$INDEX]} = $NAME || test ${ARGVS[$INDEX]} = "$SHORT_NAME";then
                error_exit "Repeat parameter: ${ARGVS[$INDEX]} , $PARAM"
            fi
        done
        ARGVS[${#ARGVS[@]}]="$NAME"
        if [ -n "$SHORT_NAME" ];then
            ARGVS[${#ARGVS[@]}]="$SHORT_NAME"
        fi
        ARG_NAME="ARGV_"`echo "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
        if [ -n "$DEFAULT_VALUE_STR" ];then
            DEFAULT_VALUE_STR=$(echo "$DEFAULT_VALUE_STR"|sed -r "s/(^=\s*)//")
            PARAM_SHOW_DEFINE="$PARAM_SHOW_DEFINE [= $DEFAULT_VALUE_STR]"
            DEFAULT_VALUE=$(echo "$DEFAULT_VALUE_STR"|sed -r "s/(^['\"])|(['\"]$)//g"|sed -r "s/\\\\(.)/\1/g")
            eval "$ARG_NAME=\$DEFAULT_VALUE"
        else
            eval "$ARG_NAME=''"
        fi
        PARAM_SHOW_INFO="    $PARAM_SHOW_DEFINE"$(echo '                                       '|sed -r "s/^.{`echo "$PARAM_SHOW_DEFINE"|wc -m`}//")$(echo "$PARAM"|sed -r "s/^.{`echo "$PARAM_STR"|wc -m`}//")
        if [[ "$NAME" =~ ^"-" ]];then
            COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS $PARAM_SHOW_INFO \n"
        else
            ARGUMENTS[${#ARGUMENTS[@]}]="$NAME"
            COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS $PARAM_SHOW_INFO \n"
        fi
    done <<EOF
$(eval "echo -e \"\$$1\"")
EOF
    # 解析匹配传入参数
    local ITEM ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=$(eval "echo \${#$3[@]}")
    for ((ARG_NUM=0; ARG_NUM < $ARG_SIZE; ARG_NUM++)); do
        ITEM=$(eval "echo \${$3[$ARG_NUM]}")
        NAME=''
        if echo "$ITEM"|grep -qiP '^((--[a-z0-9][\w\-]+(=.*)?)|(-[a-z0-9]))$'; then
            # 有参数的选项处理
            if echo "$ITEM"|grep -qiP '^--[a-z0-9][\w\-]+=.*';then
                NAME_TEMP=$(echo "$ITEM"|grep -oiP '^--[a-z0-9][\w\-]+')
                VALUE=$(echo "$ITEM"|sed -r "s/^[^=]+=//")
            else
                NAME_TEMP="$ITEM"
                VALUE=''
                for ((INDEX=0; INDEX < ${#OPTIONALS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONALS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`echo "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(echo "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        VALUE='1'
                        break
                    fi
                done
            fi
            if [ -z "$NAME" ];then
                for ((INDEX=0; INDEX < ${#OPTIONS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`echo "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(echo "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        if [ -z "$VALUE" ] && echo "$NAME_TEMP"|grep -qiP '^-[a-z0-9]$';then
                            ((ARG_NUM++))
                            VALUE=$(eval "echo \${$3[$ARG_NUM]}")
                        fi
                        if [ -z "$VALUE" ] && ! [[ $ITEM =~ = ]];then
                            error_exit "$NAME must specify a value"
                        fi
                        break
                    fi
                done
            fi
            ARGUMENTS_INDEX=${#ARGUMENTS[@]}
        elif ((${#ARGUMENTS[@]} > 0 && $ARGUMENTS_INDEX < ${#ARGUMENTS[@]})); then
            NAME=${ARGUMENTS[$ARGUMENTS_INDEX]}
            VALUE="$ITEM"
            ((ARGUMENTS_INDEX+=1))
        fi
        if [ -z "$NAME" ];then
            echo "Unknown parameter: "$ITEM
        else
            ARG_NAME="ARGV_"`echo "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
            eval "$ARG_NAME=\$VALUE"
        fi
    done
    if [ -n "$COMMENT_SHOW_ARGUMENTS" ];then
        PARAMS_SHOW_STR="Arguments: \n$COMMENT_SHOW_ARGUMENTS\n";
    fi
    if [ -n "$COMMENT_SHOW_OPTIONS" ];then
        PARAMS_SHOW_STR=$PARAMS_SHOW_STR"Options: \n$COMMENT_SHOW_OPTIONS";
    fi
    eval "$2=\$PARAMS_SHOW_STR"
    return 0
}
# 解析编译选项
# @command parse_options $var_name $options1 [$options2 ...]
# @param $var_name          写入的变量名
# @param $options1 ...      编译选项集（当选项指定 ? 会判断是否存在选项，不存在跳过）
#                       不解析选项直接使用 --xx 、-xx 或 ?--xx 、?-xx
#                       需要启用选项 xx 或 ?xx 解析后是 --enable-xx 或 --with-xx 
#                       需要禁用选项 !xx 或 ?!xx 解析后是 --disable-xx
# return 1|0
parse_options(){
    local HELP_STR=`./configure --help` OPTIONS_STR="" ITEM OPTION OPT_NAME OPT_VALUE OPTION_STR
    for ITEM in ${@:2}; do
        # 非必需选项
        if [[ "$ITEM" =~ ^"?" ]];then
            OPTION=${ITEM:1}
        else
            OPTION=$ITEM
        fi
        # 选项传入的参数拆分
        if [[ "$OPTION" =~ "=" ]];then
            OPT_NAME=${OPTION%%=*}
            OPT_VALUE="="${OPTION#*=}
        else
            OPT_NAME=$OPTION
            OPT_VALUE=""
        fi
        OPTION_STR=''
        case "$OPT_NAME" in
            # 标准选项
            --*|-*)
                if echo "$HELP_STR"|grep -qP "^\s*$OPT_NAME[\[\s=]";then
                    OPTION_STR="$OPT_NAME$OPT_VALUE"
                fi
            ;;
            # 禁用匹配选项
            ![a-zA-Z]*)
                if echo "$HELP_STR"|grep -qP "^\s*--disable-"${OPT_NAME:1}"[\[\s=]";then
                    OPTION_STR="--disable-"${OPT_NAME:1}$OPT_VALUE
                elif echo "$HELP_STR"|grep -qP "^\s*--without-"${OPT_NAME:1}"[\[\s=]";then
                    OPTION_STR="--without-"${OPT_NAME:1}$OPT_VALUE
                fi
            ;;
            # 启用匹配选项
            [a-zA-Z]*)
                if echo "$HELP_STR"|grep -qP "^\s*--enable-$OPT_NAME[\[\s=]";then
                    OPTION_STR="--enable-$OPT_NAME$OPT_VALUE"
                elif echo "$HELP_STR"|grep -qP "^\s*--with-$OPT_NAME[\[\s=]";then
                    OPTION_STR="--with-$OPT_NAME$OPT_VALUE"
                elif echo "$HELP_STR"|grep -qP "^\s*--with-$OPT_NAME-dir[\[\s=]";then
                    OPTION_STR="--with-$OPT_NAME-dir$OPT_VALUE"
                fi
            ;;
            *)
                error_exit "fail options: $OPTION"
            ;;
        esac
        if test $OPTION == $ITEM && [ -z "$OPTION_STR" ];then
            error_exit "unknown options: $ITEM"
        else
            OPTIONS_STR="$OPTIONS_STR$OPTION_STR "
        fi
    done
    eval "$1=\"\$$1\$OPTIONS_STR\""
}
# 是否存在选项
# @command exist_options $item [$options ...]
# @param $item              需要判断的选项，禁用选项加!
# @param $options           有效选项集
# return 1|0
in_options(){
    local PREFIX='enable|with' OPTION_NAME="$1"
    if [[ "$1" =~ ^'!' ]];then
        PREFIX='disable|without'
        OPTION_NAME=${1:1}
    fi
    echo "${@:1}"|grep -qP "\--(($PREFIX)-)?($OPTION_NAME)(-dir(=\S+))?"
    return $?
}
# 是否存在待添加解析选项
# @command exist_options $item [$options ...]
# @param $item              需要判断的选项，禁用选项加!
# @param $options           有效选项集
# return 1|0
in_add_options(){
    local ITEM
    for ITEM in ${@:2}; do
        if [ $1 = $ITEM ] || [ $ITEM = "?$1" ];then
            return 0
        fi
    done
    return 1
}
# make安装软件
# @command make_install [install_path]
# @param $install_path  安装目录
# return 1|0
make_install(){
    echo "make install"
    make -j $HTREAD_NUM 2>&1
    if_error "make fail!"
    make install 2>&1
    if_error "make install fail!"
    if [ -n "$1" ];then
        local PREFIX_PATH=$1
        if [[ "$1" =~ "=" ]];then
            PREFIX_PATH=${1#*=}
        fi
        echo "add env path: $PREFIX_PATH"
        # 添加动态库地址
        add_pkg_config $PREFIX_PATH
        # 添加环境目录
        if [ -e "$PREFIX_PATH/bin" ];then
            add_path $PREFIX_PATH/bin
        fi
    fi
}
# configure安装软件
# @command configure_install [$configure_options ...]
# @param $configure_options 编译安装选项
# return 1|0
configure_install(){
    make clean 2>&1
    echo "./configure $*"
    ./configure $* 2>&1
    if_error "configure fail!"
    make_install "`echo "$*"|grep -oP "\--prefix=\S+"`"
}
# cmake安装软件
# @command cmake_install [$configure_options ...]
# @param $configure_options 编译安装选项
# return 1|0
cmake_install(){
    mkdirs build-tmp
    cd build-tmp
    make clean 2>&1
    echo "$*"
    $* 2>&1
    if_error "cmake fail!"
    make_install "`echo "$*"|grep -oP "\-DCMAKE_INSTALL_PREFIX=\S+"`"
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
    echo "[ERROR] $1"
    exit 1;
}
# 创建用户及用户组
# @command add_user $username
# @param $username      用户名
# return 0
add_user(){
    if [ -n "`id $1 2>&1|grep "($1)"`" ]; then
         echo "user($1) is exists";
    else
        useradd -M -U $1
        sed -i "/^$1:*/s/\/bin\/bash/\/sbin\/nologin/" /etc/passwd
    fi
    return 0
}
# 添加环境配置
# @command add_path $path $env_name
# @param $path          要添加的目录
# @param $env_name      要添加环境变量名，默认是PATH
# return 0
add_path(){
    local ENV_NAME="$2"
    if [ -z "$2" ]; then
        ENV_NAME='PATH'
    fi
    if ! grep -qP "^export\s+$ENV_NAME=(.*:)?$1/?$" /etc/profile && ! eval echo '$'$ENV_NAME|grep -qP "^(.*:)?$1(:.*)?$"; then
        # add environment variable
        echo "export $ENV_NAME=\$$ENV_NAME:$1" >> /etc/profile
        export "$ENV_NAME"=`eval echo '$'$ENV_NAME`:"$1"
    fi
    return 0
}
# 包管理系统运行
# @command packge_manager_run $command $packge_name
# @param $command       执行的命令
# @param $packge_name   操作的包名，或变量名，变量名前面需要增加 - 如 packge_manager_run install -PACKGE_NAME
# return 1|0
packge_manager_run(){
    local COMMAND_STR
    case $1 in
        install)
            COMMAND_STR=${PACKGE_MANAGER_INSTALL_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        remove)
            COMMAND_STR=${PACKGE_MANAGER_REMOVE_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        search)
            COMMAND_STR=${PACKGE_MANAGER_SEARCH_COMMAND[$PACKGE_MANAGER_INDEX]}
        ;;
        *)
            error_exit "unknown packge manager command: $1"
        ;;
    esac
    if [ -z "$2" ];then
        error_exit "not set packge name"
    fi
    local NAME COMMAND_ARRAY_VAL PACKGE_NAME COMMAND_ARRAY
    for NAME in ${@:2}; do
        if [ ${NAME:0:1} = '-' ];then
            COMMAND_ARRAY='${#'${NAME:1}'[@]}'
            if [ `eval "echo $COMMAND_ARRAY"` -gt 1 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'['$[PACKGE_MANAGER_INDEX]']}'
            elif [ `eval "echo $COMMAND_ARRAY"` -gt 0 ];then
                COMMAND_ARRAY_VAL='${'${NAME:1}'[0]}'
            else
                error_exit "not find packge name: $NAME"
            fi
            PACKGE_NAME=`eval "echo $COMMAND_ARRAY_VAL"`
            if [ "$PACKGE_NAME" = '-' ];then
                continue;
            fi
        else
            PACKGE_NAME=$NAME
        fi
        if [ -z "$PACKGE_NAME" ];then
            error_exit "empty packge name: $NAME"
        fi
        $COMMAND_STR $PACKGE_NAME 2> /dev/null
    done
}
# 工具集安装
# @command tools_install $tool1 [$tool2 ...]
# @param $tool1 ...     工具名集（工具名全部是通用的）
# return 0
tools_install(){
    local TOOL
    for TOOL in $*; do
        if ! if_command $TOOL;then
            packge_manager_run install $TOOL 2> /dev/null
            if ! if_command $TOOL;then
                error_exit "install tool: $TOOL fail!"
            fi
        fi
    done
    return 0
}
# 判断命令是否存在
# @command if_command $name
# @param $name          包名
# return 1|0
if_command(){
    if which $1 2>&1|grep -q "/$1";then
        return 0
    fi
    return 1
}
# 判断命令是否存在多个不同版本
# @command if_many_version $name $option1 [$option2 ...]
# @param $name          包名
# @param $option1       命令对比参数，一般以版本号对比
# return 1|0
if_many_version(){
    if if_command $1;then
        local ITEM NEXT_VERSION PREV_VERSION
        for ITEM in `which -a $1`; do
            NEXT_VERSION=`$ITEM ${@:2} 2>&1`
            if [ -z "$PREV_VERSION" ];then
                PREV_VERSION=$NEXT_VERSION
            elif test "$NEXT_VERSION" != "$PREV_VERSION";then
                return 0
            fi
        done
    fi
    return 1
}
# 判断库是否存在
# @command if_lib $name [$if $version]
# @param $name          库名
# @param $if            判断版本条件：>=,>,<=,<,==
# @param $version       判断版本号
# return 1|0
if_lib(){
    # ldconfig 是动态库管理工具，主要是通过配置文件 /etc/ld.so.conf 来管理动态库所在目录
    # 安装pkg-config
    # pkg-config 是三方库管理工具，以.pc为后缀的文件来配置不同的三方头文件或库文件
    # 一般三方库需要有个以 -devel 为后缀的配置工具名安装后就会把以 .pc 为后缀的文件写到到 pkg-config 默认管理目录
    # 例如：安装openssl后需要再安装openssl-devel才可以使用 pkg-config 查看 openssl
    # 安装pkg-config
    if ! if_command pkg-config;then
        packge_manager_run install -PKGCONFIG_PACKGE_NAMES
    fi
    if ! if_command pkg-config;then
        # 获取最新版
        get_version PKG_CONFIG_VERSION https://pkg-config.freedesktop.org/releases/ 'pkg-config-\d+\.\d+\.tar\.gz'
        echo "install pkg-config-$PKG_CONFIG_VERSION"
        # 下载
        download_software https://pkg-config.freedesktop.org/releases/pkg-config-$PKG_CONFIG_VERSION.tar.gz
        # 编译安装
        configure_install --with-internal-glib --prefix=$INSTALL_BASE_PATH/pkg-config/$PKG_CONFIG_VERSION
    fi
    if pkg-config --exists "$1";then
        if [ -n "$2" ] && [ -n "$3" ] && ! pkg-config --cflags --libs "$1 $2 $3" > /dev/null;then
            return 1
        fi
        return 0
    fi
    return 1
}
# 随机生成密码
# @command random_password $password_val [$size] [$group]
# @param $password_val      生成密码写入变量名
# @param $size              密码长度，默认20
# @param $group             密码组合正则
#                           包含：数字、字母大小写、~!@#$%^&*()_-=+,.;:?/\|
#                           默认全部组合
# return 1|0
random_password(){
    local PASSWORD_CHARS_STR='qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM~!@#$%^&*()_-=+,.;:?/\|'
    if [ -n "$3" ];then
        PASSWORD_CHARS_STR=`echo "$PASSWORD_CHARS_STR"|grep -oP "$3+"`
        if_error "password group error: $3"
    fi
    local PASSWORD_CHATS_LENGTH=`echo $PASSWORD_CHARS_STR|wc -m` PASSWORD_STR='' PASSWORD_INDEX_START='' PASSWORD_SIZE=25
    if [ -n "$2" ]; then
        PASSWORD_SIZE=`expr $2 + 0`
        if_error "password size error: $2"
        if test $PASSWORD_SIZE -lt 1 || test $PASSWORD_SIZE -gt 1000; then
            error_exit "password size range error: $2"
        fi
    fi
    for ((I=0; I<$PASSWORD_SIZE; I++)); do
         PASSWORD_INDEX_START=`expr $RANDOM % $PASSWORD_CHATS_LENGTH`
         PASSWORD_STR=$PASSWORD_STR${PASSWORD_CHARS_STR:$PASSWORD_INDEX_START:1}
    done
    eval "$1='$PASSWORD_STR'"
}
# 常规公式计算
# @command math_compute $result $formula [$scale]
# @param $result            计算结果写入变量名
# @param $formula           计算公式
# @param $scale             计算小数精度位数，默认是0
#                           支持运算：+-*/^%
# return 1|0
math_compute(){
    if ! if_command bc; then
        packge_manager_run install bc
    fi
    local SCALE_NUM=0
    if [ -n "$3" ]; then
        SCALE_NUM=`echo "$3"|grep -oP '^\d+'`
        SCALE_NUM=`echo "$SCALE_NUM"|awk '{if($1 == ""){print "0"}else{print $1}}'`
    fi
    RESULT_STR=`echo "scale=$SCALE_NUM; $2"|bc|sed 's/\\\\//'`
    RESULT_STR=`echo $RESULT_STR|awk -F '.' '{if($1==""){print "0."$2}else{print $1"."$2}}'|sed 's/ //g'|grep -oP "^\d+(\.\d{0,$SCALE_NUM})?"|grep -oP '^\d+(\.\d*[1-9])?'`
    eval "$1='$RESULT_STR'"
}
# 运行安装脚本
# @command run_install_shell $shell_file $version_num [$other ...]
# @param $shell_file        安装脚本名
# @param $version_num       安装版本号
# @param $other             其它安装参数集
# return 1|0
run_install_shell (){
    if [ -z "$1" ] || [ ! -e "$CURRENT_PATH/$1" ]; then
        error_exit "install shell error: $1"
    fi
    if [ -z "$2" ]; then
        error_exit "must install version num"
    fi
    local CURRENT_PWD=`pwd`
    cd $CURRENT_PATH
    bash ${@:1}
    if_error "run $1 fail"
    cd $CURRENT_PWD
    source /etc/profile
}
# 初始化安装
# @command start_install [$version_name] [$define_name] [$options_name]
# @param $version_name      版本号写入变量名
# @param $define_name       安装脚本追加命令参数定义
# @param $options_name      参数数组名
# return 1|0
init_install (){
    local INSTALL_ARGVS=${3-CALL_INPUT_ARGVS}
    parse_install_param ${2-''} $INSTALL_ARGVS
    if (($# > 2)) && [ -z "$ARGV_version" ];then
        error_exit "unknown installation version"
    fi
    # 版本处理
    if [ -z "$ARGV_version" ] || [[ $ARGV_version == "new" ]]; then
        get_version $1 "$VERSION_URL" "$VERSION_MATCH" "$VERSION_RULE"
        if [ -z "$ARGV_version" ];then
            eval "echo $""$1"
            exit 0;
        fi
    elif echo "$ARGV_version"|grep -qP "$VERSION_RULE";then
        eval "$1=\"$ARGV_version\""
    else
        error_exit "unknown version $ARGV_version"
    fi
    local INSTALL_VERSION=`eval "echo \$"$1` INSTALL_VERSION_MIN=`eval "echo \$"$1"_MIN"`
    if ps aux|grep -P "$INSTALL_NAME-install\.sh\s+(new|\d+\.\d+)"|grep -vqP "\s+$$\s+"; then
        if [[ -n "$ARGV_reset" && "$ARGV_reset" =~ ^[1-2]$ ]];then
            echo "$INSTALL_NAME already installing"
        else
            error_exit "$INSTALL_NAME already installing"
        fi
    fi
    # 安装目录
    INSTALL_PATH="$INSTALL_BASE_PATH/$INSTALL_NAME/"
    if [ -e "$INSTALL_PATH$INSTALL_VERSION/" ] && find "$INSTALL_PATH$INSTALL_VERSION/" -type f -executable|grep -qP "$INSTALL_NAME|bin";then
        echo "$INSTALL_NAME-$INSTALL_VERSION Installation directory is not empty: $INSTALL_PATH$INSTALL_VERSION/"
        if [[ -z "$ARGV_reset" || ! "$ARGV_reset" =~ ^[1-2]$ ]];then
            exit 0
        fi
    fi
    echo "install $INSTALL_NAME-$INSTALL_VERSION"
    echo "install path: $INSTALL_PATH"
    if [ -n "$INSTALL_VERSION_MIN" ] && if_version "$INSTALL_VERSION" "<" "$INSTALL_VERSION_MIN"; then
        error_exit "install min version: $INSTALL_VERSION_MIN"
    fi
    # 安装必需工具
    tools_install gcc make
    if ! if_command ntpdate; then
        packge_manager_run install ntpdate 2> /dev/null
    fi
    if ! if_command ntpdate; then
        # 更新系统时间
        ntpdate -u ntp.api.bz 2>&1 &>/dev/null &
    fi
    # 加载环境配置
    source /etc/profile
    # 内存空间不够
    if ! free -tg|grep -qi swap && if_version `free -tg|tail -1|grep -oP '\d+'|head -1` '<' '3';then
        dd if=/dev/zero of=/swap bs=1024 count=2M
        mkswap /swap
        swapon /swap
        echo "/swap swap swap sw 0 0" >> /etc/fstab
    fi
    return 0
}
# 提取安装参数
CALL_INPUT_ARGVS=()
for ((INDEX=1;INDEX<=$#;INDEX++));do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=${@:$INDEX:1}
done
unset INDEX
# 加载配置
source config.sh
# 判断系统适用哪个包管理器
if if_command yum;then
    PACKGE_MANAGER_INDEX=0
    # epel-release 第三方软件依赖库EPEL，给yum、rpm等工具使用
    #yum -y install epel-release
    # 创建元数据缓存
    #yum makecache 2>&1 &>/dev/null
    yum -y update nss 2>&1 &>/dev/null &
elif if_command apt;then
    PACKGE_MANAGER_INDEX=1
elif if_command dnf;then
    PACKGE_MANAGER_INDEX=2
elif if_command pkg;then
    PACKGE_MANAGER_INDEX=3
else
    error_exit 'not packge manager'
fi
# 网络基本工具安装
tools_install curl wget
# 获取内核数
if [ -n "$INSTALL_HTREAD_NUM" ];then
    HTREAD_NUM=$INSTALL_HTREAD_NUM
else
    HTREAD_NUM=`lscpu |grep '^CPU(s)'|grep -oP '\d+$'`
fi
# 提取工作目录
OLD_PATH=`pwd`
if [[ "$0" =~ '/' ]]; then
    cd "`echo "$0" | grep -oP '(/?[^/]+/)+'`"
    CURRENT_PATH=`pwd`
    cd $OLD_PATH
else
    CURRENT_PATH=$OLD_PATH
fi

