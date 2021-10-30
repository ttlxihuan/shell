#!/bin/bash
if [ "$0" = 'basic.sh' ] || [[ "$0" == */basic.sh ]];then
    error_exit "basic.sh 脚本是共用文件必需使用source调用"
fi
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
        if_error "创建目录失败: $1"
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
            error_exit "未知版本判断条件：$2"
        ;;
    esac
    if [ -n "$RESULT" ]; then
        return 0;
    fi
    return 1;
}
# 获取版本
# @command get_version $var_name $url $version_path_rule [$version_rule]
# @param $var_name          获取版本号变量名
# @param $url               获取版本号的HTML页面地址
# @param $version_path_rule 匹配版本号的正则规则（粗级匹配，获取所有版本号再排序提取最大的）
# @param $version_rule      提取版本号的正则规则（精准匹配，直接对应的版本号）
# return 1|0
get_version(){
    local VERSION_RULE="$4" VERSION
    if [ -z "$4" ];then
        VERSION_RULE='\d+(\.\d+){1,2}'
    fi
    VERSION=`curl $2 -LkN 2>/dev/null| grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
    if [ -z "$VERSION" ];then
        error_exit "获取版本数据失败: $2"
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
    echo "下载并解压：$1"
    if [ -z "$DIR_NAME" ];then
        error_exit "下载目录找不到"
    fi
    chdir $INSTALL_NAME
    # 重新下载再安装
    if [ "$ARGV_reset" = '3' -a -e "$FILE_NAME" ];then
        echo "删除下载文件重新下载：$FILE_NAME"
        rm -f $FILE_NAME
    fi
    if [[ "$ARGV_reset" =~ ^[2-3]$ ]] && [ -d "$DIR_NAME" ];then
        echo "删除解压目录重新解压：$DIR_NAME"
        rm -rf $DIR_NAME
    fi
    if [ ! -e "$FILE_NAME" ];then
        if ! wget --no-check-certificate -T 7200 $1; then
            curl -OLkN --connect-timeout 7200 $1
        fi
        if [ $? -ne 0 ];then
            mv $FILE_NAME "`date +'%Y_%m_%d_%H_%M_%S'`_error_$FILE_NAME"
            error_exit "下载失败: $1"
        fi
    else
        echo '已经存在下载文件：'$FILE_NAME
    fi
    if [ ! -d "$DIR_NAME" ];then
        echo '解压下载文件：'$FILE_NAME
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
                error_exit "未知解压文件: $FILE_NAME"
            ;;
        esac
        if_error "解压文件失败: $FILE_NAME"
        echo "下载文件的sha256: "`sha256sum $FILE_NAME`
    fi
    cd $DIR_NAME
    if_error "解压目录找不到: $DIR_NAME"
    return 0
}
# 解析安装命令参数
# 注意：此命令会提取全局变量 DEFINE_INSTALL_PARAMS 和 DEFINE_INSTALL_TYPE
# DEFINE_INSTALL_PARAMS 是安装额外定义的参数选项，配置参数规则：
#      [name]              定义参数
#      [-n, --name]        定义无值选项
#      [-n, --name='']     带选项值的选项
# DEFINE_INSTALL_TYPE 是指定安装类型，configure、make、cmake，安装类型决定是否开放--options参数
# @command parse_install_param $options_name
# @param $options_name      命令参数数组名
# return 1|0
parse_install_param(){
    local _PARSE_DEFINE_PARAMS_STR_ _PARSE_DEFINE_PARAMS_="
[version]指定安装版本，不传则是获取最新稳定版本号，传new安装最新版，传指定版本号则安装指定版本
[-h, --help]显示安装脚本帮助信息
[--install-path='/usr/local'] 安装根目录，各软件服务安装最终目录是 安装根目录/软件名/版本号
# 没有特殊要求建议安装根目录不设置到非系统所在硬盘目录下
[-r, --reset=0]重新安装：0 标准安装，1 重新安装 2 重新解压再安装 3 重新下载解压再安装，默认0
[--data-free=ask]数据空间不够用时处理
# auto 自动选择，空间不足时搜索空间够用的硬盘使用
# save 保存自动选择，主要是保存虚拟内存变化，保存重启仍然有效
# ask 询问，可以选择性的允许空间处理
# ignore 忽略，空间不足时不能保证安装成功
# 数据空间包括编译目录硬盘和内存大概最少剩余空间
# 处理操作有：编译目录转移，自动添加虚拟内存等
"
    if [ -n "$DEFINE_INSTALL_TYPE" ];then
        _PARSE_DEFINE_PARAMS_=$_PARSE_DEFINE_PARAMS_"
[-j, --make-jobs=avg]编译同时允许N个任务，可选值有 max|avg|number 
# max 当前CPU数
# avg 当前CPU半数+1
# number 是指定的数值。
# 任务多编译快且资源消耗也大（不建议超过CPU核数），当编译因进程被系统杀掉时可减少此值重试。
[-o, --options='']添加${DEFINE_INSTALL_TYPE}选项，使用前请核对选项信息。
"
        if [ "$DEFINE_INSTALL_TYPE" = 'configure' ];then
            _PARSE_DEFINE_PARAMS_=$_PARSE_DEFINE_PARAMS_"
# 增加${DEFINE_INSTALL_TYPE}选项，支持以下三种方式传参：
# 1、原样选项 --xx 、-xx 或 ?--xx 、?-xx
# 2、启用选项 xx 或 ?xx 解析后是 --enable-xx 或 --with-xx 
# 3、禁用选项 !xx 或 ?!xx 解析后是 --disable-xx
# 选项前面的?是在编译选项时会查找选项是否存在，如果不存在则丢弃，存在则附加
# 选项前面的!是禁用某个选项，解析后会存在该选项则附加
# 选项多数是有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
        elif [ -n "$DEFINE_INSTALL_TYPE" ];then
            _PARSE_DEFINE_PARAMS_=$_PARSE_DEFINE_PARAMS_"
# 增加${DEFINE_INSTALL_TYPE}原样选项，选项按${DEFINE_INSTALL_TYPE}标准即可。
# 选项部分是有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
        fi
    fi
    if [ -n "$DEFINE_INSTALL_PARAMS" ];then
        _PARSE_DEFINE_PARAMS_=$_PARSE_DEFINE_PARAMS_$DEFINE_INSTALL_PARAMS
    fi
    parse_command_param _PARSE_DEFINE_PARAMS_ _PARSE_DEFINE_PARAMS_STR_ $1
    if [ -n "$ARGV_help" ];then
        echo -e "Description:
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
        bash ${INSTALL_NAME}-install.sh 1.1.1";
    if [ "$DEFINE_INSTALL_TYPE" = 'configure' ];then
        echo -e "
    安装最新稳定版本${INSTALL_NAME}且指定安装选项:
        bash ${INSTALL_NAME}-install.sh new --options=\"?ext1 ext2\"
"
    elif [ -n "$DEFINE_INSTALL_TYPE" ];then
        echo -e "
    安装最新稳定版本${INSTALL_NAME}且指定安装选项:
        bash ${INSTALL_NAME}-install.sh new --options=\"opt1 opt2\"
"
    fi
        echo -e "
    安装脚本会在脚本所有目录创建安装目录，此目录用于下载和编译安装包。
    当后续再次安装相同版本时，已经存在的安装包将不再下载而是直接使用。
    如果安装多台服务器可直接复制安装目录及安装包，这样就不会再下载而是直接安装处理。
"
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
        if [ -z "$PARAM" ] || printf '%s' "$PARAM"|grep -qP '^\s*$'; then
            continue;
        fi
        if printf '%s' "$PARAM"|grep -qP '^\s*#';then
            PARAM='                                '$(printf '%s' "$PARAM"|sed -r 's/^\s*#\s*//')" \n"
            if [[ "$NAME" == -* ]];then
                COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM"
            elif [ -n "$NAME" ];then
                COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM"
            else
                error_exit "备注无匹配参数信息：$PARAM"
            fi
            continue;
        fi
        PARAM_STR=$(printf '%s' "$PARAM"|grep -oiP "^\s*\[\s*((-[a-z0-9]\s*,\s*)?--[a-z0-9][\w\-]+|[a-z0-9][\w\-]+)(\s*=\s*(\w+|\"([^\"]|\\\\.)*\"|'([^']|\\\\.)*'))?\s*\]\s*")
        if [ -z "$PARAM_STR" ];then
            error_exit "定义参数解析失败：$PARAM"
        fi
        PARAM_INFO_STR=`printf '%s' "$PARAM_STR"|sed -r "s/(^\s*\[\s*)|(\s*\]\s*$)//g"`
        PARAM_NAME_STR=`printf '%s' "$PARAM_INFO_STR"|grep -oP '^[^=]+'`
        DEFAULT_VALUE_STR=$(printf '%s' "$PARAM_INFO_STR"|grep -oP "=\s*(\w+|\"([^\"]|\\\\.)*\"|'([^']|\\\\.)*')$")
        if printf '%s' "$PARAM_NAME_STR"|grep -qP '^-{1,2}';then
            SHORT_NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oiP '^-[a-z0-9]'`
            NAME=`printf '%s' "$PARAM_NAME_STR"|grep -oiP '\-\-[a-z0-9][\w\-]+'`
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
            NAME=`printf '%s' $PARAM_NAME_STR|grep -oiP '^[a-z0-9][\w\-]+'`
            PARAM_SHOW_DEFINE="$NAME"
        fi
        for ((INDEX=0; INDEX < ${#ARGVS[@]}; INDEX++)); do
            if test ${ARGVS[$INDEX]} = $NAME || test ${ARGVS[$INDEX]} = "$SHORT_NAME";then
                error_exit "不能定义重名参数: ${ARGVS[$INDEX]} , $PARAM"
            fi
        done
        ARGVS[${#ARGVS[@]}]="$NAME"
        if [ -n "$SHORT_NAME" ];then
            ARGVS[${#ARGVS[@]}]="$SHORT_NAME"
        fi
        ARG_NAME="ARGV_"`printf '%s' "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
        if [ -n "$DEFAULT_VALUE_STR" ];then
            DEFAULT_VALUE_STR=$(printf '%s' "$DEFAULT_VALUE_STR"|sed -r "s/(^=\s*)//")
            PARAM_SHOW_DEFINE="$PARAM_SHOW_DEFINE [= $DEFAULT_VALUE_STR]"
            DEFAULT_VALUE=$(printf '%s' "$DEFAULT_VALUE_STR"|sed -r "s/(^['\"])|(['\"]$)//g"|sed -r "s/\\\\(.)/\1/g")
            eval "$ARG_NAME=\$DEFAULT_VALUE"
        else
            eval "$ARG_NAME=''"
        fi
        INDEX=`echo $[ $(printf '%s' "$PARAM_SHOW_DEFINE"|wc -m) + 4 ]`
        if (($INDEX >= 32));then
            PARAM_SHOW_INFO="\n                                "
        else
            PARAM_SHOW_INFO=$(echo '                                '|sed -r "s/^.{$INDEX}//")
        fi
        PARAM_SHOW_INFO="    $PARAM_SHOW_DEFINE$PARAM_SHOW_INFO"$(printf '%s' "$PARAM"|sed -r "s/^.{1,`echo $(printf '%s' "$PARAM_STR"|wc -m)`}//")
        if [[ "$NAME" == -* ]];then
            COMMENT_SHOW_OPTIONS="$COMMENT_SHOW_OPTIONS$PARAM_SHOW_INFO \n"
        else
            ARGUMENTS[${#ARGUMENTS[@]}]="$NAME"
            COMMENT_SHOW_ARGUMENTS="$COMMENT_SHOW_ARGUMENTS$PARAM_SHOW_INFO \n"
        fi
    done <<EOF
$(eval "echo -e \"\$$1\"")
EOF
    # 解析匹配传入参数
    local ITEM ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=$(eval "echo \${#$3[@]}")
    for ((ARG_NUM=0; ARG_NUM < $ARG_SIZE; ARG_NUM++)); do
        eval "ITEM=\${$3[$ARG_NUM]}"
        if [ -z "$ITEM" ];then
            continue
        fi
        NAME=''
        if printf '%s' "$ITEM"|grep -qiP '^((--[a-z0-9][\w\-]+(=.*)?)|(-[a-z0-9]))$'; then
            # 有参数的选项处理
            if printf '%s' "$ITEM"|grep -qiP '^--[a-z0-9][\w\-]+=.*';then
                NAME_TEMP=$(printf '%s' "$ITEM"|grep -oiP '^--[a-z0-9][\w\-]+')
                VALUE=$(printf '%s' "$ITEM"|sed -r "s/^[^=]+=//")
            else
                NAME_TEMP="$ITEM"
                VALUE=''
                for ((INDEX=0; INDEX < ${#OPTIONALS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONALS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(printf '%s' "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        VALUE='1'
                        break
                    fi
                done
            fi
            if [ -z "$NAME" ];then
                for ((INDEX=0; INDEX < ${#OPTIONS[@]}; INDEX++)); do
                    OPTIONS_TEMP=${OPTIONS[$INDEX]}
                    if [ "$OPTIONS_TEMP" != "`printf '%s' "$OPTIONS_TEMP"|sed -r "s/$NAME_TEMP($|,)//"`" ];then
                        NAME=$(printf '%s' "$OPTIONS_TEMP"|sed -r "s/(-[A-Za-z0-9]\s*,\s*)?--//")
                        if [ -z "$VALUE" ] && printf '%s' "$NAME_TEMP"|grep -qiP '^-[a-z0-9]$';then
                            ((ARG_NUM++))
                            eval "VALUE=\${$3[$ARG_NUM]}"
                        fi
                        if [ -z "$VALUE" ] && ! [[ $ITEM =~ = ]] && (($ARG_NUM >= $ARG_SIZE));then
                            error_exit "$NAME 必需指定一个值"
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
            echo "未知参数: "$ITEM
        else
            ARG_NAME="ARGV_"`printf '%s' "$NAME"|sed -r "s/^-{1,2}//"|sed "s/-/_/g"`
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
                error_exit "解析选项语法错误: $OPTION"
            ;;
        esac
        if test $OPTION == $ITEM && [ -z "$OPTION_STR" ];then
            error_exit "未知编译选项: $ITEM"
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
# @command make_install [install_path] [$make_options ...]
# @param $install_path      安装目录
# @param $make_options      编译选项
# return 1|0
make_install(){
    echo "make 编译安装"
    make -j $HTREAD_NUM ${@:2} 2>&1
    if_error "make 编译失败"
    make install 2>&1
    if_error "make 安装失败"
    if [ -n "$1" ];then
        local PREFIX_PATH=$1
        if [[ "$1" =~ "=" ]];then
            PREFIX_PATH=${1#*=}
        fi
        echo "添加环境变量PATH: $PREFIX_PATH"
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
    if_error "configure 编译配置失败"
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
    if_error "cmake 编译安装失败"
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
# 创建用户（包含用户组、可执行shell、密码）
# @command add_user $username [$shell_name] [$password]
# @param $username      用户名
# @param $shell_name    当前用户可调用的shell脚本名，默认是/sbin/nologin
# @param $password      用户密码，不指定则不创建密码
# return 0
add_user(){
    if [ -n "`id $1 2>&1|grep "($1)"`" ]; then
         echo "用户：$1 已经存在无需再创建";
    else
        local RUN_FILE='/sbin/nologin'
        if [ -n "$2" -a -e "$2" ];then
            RUN_FILE=$2
        fi
        useradd -M -U -s $RUN_FILE $1
        if [ -n "$3" ];then
            if echo "$3"|passwd --stdin $1; then
                echo "创建用户：$1 密码: $3"
            fi
        fi
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
# 添加可执行文件链接到/usr/local/bin/目录内
# 注意：部分调用方式不会获取用户补充的环境变量PATH数据（比如：crontab定时器自动调用），所以必需添加到默认环境变量PATH的目录中，而/usr/local/bin/目录就是其中一个。
# @command add_local_run $path [$run_name ...]
# @param $path          要添加的可执行文件目录
# @param $run_name      指定可执行文件名，可以是规则，不指定则全部添加
# return 0
add_local_run(){
    # 添加执行文件连接
    local RUN_FILE NUM SET_ALLOW
    for RUN_FILE in `find $1 -executable`; do
        if (($# > 1));then
            SET_ALLOW=0
            for((NUM=1;NUM<=$#;NUM++));do
                if [[ ${RUN_FILE##*/} == ${@:$NUM:1} ]];then
                    SET_ALLOW=1
                    break
                fi
            done
        else
            SET_ALLOW=1
        fi
        if (($SET_ALLOW > 0));then
            ln -svf $RUN_FILE /usr/local/bin/${RUN_FILE##*/}
        fi
    done
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
            error_exit "未知包管理命令: $1"
        ;;
    esac
    if [ -z "$2" ];then
        error_exit "最少指定一个要安装的包名"
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
                error_exit "找不到配置的安装包名: $NAME"
            fi
            PACKGE_NAME=`eval "echo $COMMAND_ARRAY_VAL"`
            if [ "$PACKGE_NAME" = '-' ];then
                continue;
            fi
        else
            PACKGE_NAME=$NAME
        fi
        if [ -z "$PACKGE_NAME" ];then
            error_exit "安装包名解析为空: $NAME"
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
                error_exit "安装工具失败: $TOOL"
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
        if [ -n "$2" -a -n "$3" ] && ! pkg-config --cflags --libs "$1 $2 $3" > /dev/null;then
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
        if_error "密码包含的字符无效: $3"
    fi
    local PASSWORD_CHATS_LENGTH=`echo $PASSWORD_CHARS_STR|wc -m` PASSWORD_STR='' PASSWORD_INDEX_START='' PASSWORD_SIZE=25
    if [ -n "$2" ]; then
        if ! [[ "$2" =~ ^[1-9][0-9]*$ ]];then
            error_exit "生成密码位数必需是整数，现在是：$2"
        fi
        if (($2 < 0 || $2 > 100));then
            error_exit "生成密码位数范围是：1~99，现在是：$2"
        fi
        PASSWORD_SIZE=$2
    fi
    for ((I=0; I<$PASSWORD_SIZE; I++)); do
         PASSWORD_INDEX_START=`expr $RANDOM % $PASSWORD_CHATS_LENGTH`
         PASSWORD_STR=$PASSWORD_STR${PASSWORD_CHARS_STR:$PASSWORD_INDEX_START:1}
    done
    eval "$1='$PASSWORD_STR'"
}
# 常规高精度公式计算
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
        NEXT=`printf '%s' "$PARSE_STRING"|grep -oP "^.*?$3"`
        ITEM=`printf '%s' "$NEXT"|sed -r "s/(^\s+|\s*$3$)//g"`
        if [ -z "$ITEM" ] || ! printf '%s' "$ITEM"|grep -qP "^$4$";then
            return $((`printf '%s' "$2"|wc -m` - `printf '%s' "$PARSE_STRING"|wc -m` + 1))
        fi
        PARSE_STRING=${PARSE_STRING:`printf '%s' "$NEXT"|wc -m`}
        # 去重处理
        for ((INDEX=0; INDEX < `eval "\${#$1[@]}"`; INDEX++)); do
            if test `eval "\${$1[$INDEX]}"` = $ITEM ;then
                continue 2
            fi
        done
        eval "$1[\${#$1[@]}]"="\$ITEM"
    done
    return 0
}
# 运行安装脚本
# @command run_install_shell $shell_file $version_num [$other ...]
# @param $shell_file        安装脚本名
# @param $version_num       安装版本号
# @param $other             其它安装参数集
# return 1|0
run_install_shell (){
    if [ -z "$1" ] || [ ! -e "$SHELL_WORK_PATH/$1" ]; then
        error_exit "安装的shell脚本不存在: $1"
    fi
    if [ -z "$2" ]; then
        error_exit "安装shell脚本必需指定的安装的版本号参数"
    fi
    local CURRENT_PWD=`pwd`
    cd $SHELL_WORK_PATH
    bash ${@:1}
    if_error "安装shell脚本失败：$1"
    cd $CURRENT_PWD
    source /etc/profile
}
# 获取系统名及版本号
# @command get_os
# return 1|0
get_os(){
    if [ -e '/etc/os-release' ];then
        source /etc/os-release;
        echo "$ID $VERSION_ID"|tr '[:upper:]' '[:lower:]'
    fi
}
# 获取当前IP地址，内网是局域IP，写入全局变量SERVER_IP
# @command get_ip
# return 1|0
get_ip(){
    SERVER_IP='127.0.0.1'
    if ! if_command ifconfig;then
        packge_manager_run install net-tools
    fi
    if if_command ifconfig;then
        SERVER_IP=`ifconfig|grep -P '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -o -m 1|head -n 1`
    else
        echo '没有ifconfig命令，无法获取当前IP，将使用默认地址：'$SERVER_IP >&2
    fi
}
# 当前安装内存空间要求，不够将添加虚拟内存扩充
# @command memory_require $min_size
# @param $min_size          安装脚本最低内存大小，G为单位
# return 1|0
memory_require(){
    local ASK_INPUT CURRENT_MEMORY DIFF_SIZE
    # 总内存G
    CURRENT_MEMORY=`cat /proc/meminfo|grep -P '^(MemTotal|SwapTotal):'|awk '{count+=$2} END{print count/1048576}'`
    # 剩余内存G
    # CURRENT_MEMORY=cat /proc/meminfo|grep -P '^(MemFree|SwapFree):'|awk '{count+=$2} END{print count/1048576}'
    math_compute DIFF_SIZE "$1 - $CURRENT_MEMORY"
    if (($DIFF_SIZE > 0)) && (ask_select ASK_INPUT "内存最少 ${1}G，现在只有 ${CURRENT_MEMORY}G，是否增加虚拟内存 ${DIFF_SIZE}G：" || [ "$ASK_INPUT" = 'y' ]);then
        local BASE_PATH SWAP_PATH
        path_require $DIFF_SIZE / BASE_PATH;
        SWAP_PATH=$BASE_PATH/swap
        echo '创建虚拟内存交换区：'$SWAP_PATH
        # 创建一个空文件区，并以每块bs字节重复写count次数且全部写0，主要是为防止内存溢出或越权访问到异常数据
        dd if=/dev/zero of=$SWAP_PATH bs=1024 count=8M
        # 将/swap目录设置为交换区
        mkswap $SWAP_PATH
        # 修改此目录权限
        chmod 0600 $SWAP_PATH
        # 开启/swap目录交换空间，开启后系统将建立虚拟内存，大小为 bs * count
        swapon $SWAP_PATH
        if [ "$ARGV_data_free" = 'save' ] || (ask_select ASK_INPUT '虚拟内存交换是否写入系统配置：' || [ "$ASK_INPUT" = 'y' ]);then
            # 写入配置文件，重启系统自动开启/swap目录交换空间
            echo "$SWAP_PATH swap swap sw 0 0" >> /etc/fstab
        fi
    fi
}
# 安装编译工作目录剩余空间要求
# @command work_path_require $min_size
# @param $min_size          安装编译工作目录最低磁盘剩余空间大小，G为单位
# return 1|0
work_path_require(){
    local BASE_PATH MIN_SIZE
    # 如果目录已经存在文件则需要获取当前目录的空间再剥除，这块操作比较耗时间
    math_compute MIN_SIZE "$1-`du --max-depth=1 $CURRENT_PATH/$INSTALL_NAME|tail -1|awk '{print$1}'`/1048576"
    if (($MIN_SIZE > 0));then
        path_require $MIN_SIZE $CURRENT_PATH BASE_PATH;
        # 有匹配的工作目录，直接转移工作目录
        if [ -n "$BASE_PATH" ];then
            mkdirs $BASE_PATH/shell-install
            CURRENT_PATH="$BASE_PATH/shell-install"
        fi
    fi
}
# 安装目录剩余空间要求
# @command install_path_require $min_size $path
# @param $min_size          安装目录最低磁盘剩余空间大小，G为单位
# @param $path              要判断的目录，默认安装根目录
# return 1|0
install_path_require(){
    if ((`df ${2-$INSTALL_BASE_PATH}|awk '{print $4}'|tail -1` / 1048576 < $1 ));then
        echo "安装目录 $2 所在硬盘 `df ./|awk '{print $1}'|tail -1` 剩余空间不足：${1}G ，无法进行安装！"
        if [ "$ARGV_data_free" = 'ignore' ];then
            echo '忽略空间不足'
            return 0
        fi
        exit 1
    fi
}
# 获取指定目录对应挂载磁盘剩余空间要求
# @command path_require $min_size $path $path_name
# @param $min_size          安装脚本最低磁盘剩余空间大小，G为单位
# @param $path              要判断的目录
# @param $path_name         有空余的目录
# return 1|0
path_require(){
    if ((`df $2|awk '{print $4}'|tail -1` / 1048576 < $1 ));then
        echo "目录 $2 所在硬盘 `df ./|awk '{print $1}'|tail -1` 剩余空间不足：${1}G"
        if [[ "$ARGV_data_free" =~ ^(auto|save|ask)$ ]];then
            search_free_path $3 $(($1 * 1048576))
        else
            echo '忽略空间不足'
        fi
    fi
}
# 获取可用空间达到的硬盘绑定目录
# @command search_free_path $path_name $min_size
# @param $path_name         获取有效目录写入变量名
# @param $min_size          最低磁盘剩余空间大小，K为单位
# return 1|0
search_free_path(){
    local ITEM ASK_INPUT
    while read ITEM; do
        if [ -n "$ITEM" ] && (ask_select ASK_INPUT `printf "文件系统：%s 挂载目录：%s 可用空间：%s 是否选用：" $ITEM` || [ "$ASK_INPUT" = 'y' ]);then
            ITEM=$(echo "$ITEM"|awk '{print $2}')
            eval "$1=\$ITEM"
            return 0
        fi
    done <<EOF
`df -T|awk 'NR >1 && $5 > '$2' && $2 !~ /*tmpfs/ && $6 > 10 {$5=$5/1048576; print $1,$7,$5}'`
EOF
    error_exit "没有合适空间，终止执行！"
}
# 询问选项处理
# @command ask_select $select_name $msg [$options]
# @param $select_name       询问获取输入内容写入变量名
# @param $msg               询问提示文案
# @param $options           询问输入选项，多个使用/分开，默认是 y/n
# return 1|0
ask_select(){
    if [ "$ARGV_data_free" != 'ask' ];then
        return 0
    fi
    local INPUT MSG_TEXT REGEXP_TEXT ATTEMPT=1  OPTIONS=$(printf '%s' "${3-y/n}"|sed 's/ //g')
    MSG_TEXT="$2 请输入：[ $OPTIONS ]"
    REGEXP_TEXT=$(printf '%s' "$OPTIONS"|sed 's/\//|/g')
    while [ -z "$INPUT" ]; do
        printf '%s' "$MSG_TEXT"
        read INPUT
        if printf '%s' "$INPUT"|grep -qP "^($REGEXP_TEXT)$";then
            break
        fi
        INPUT=''
        if ((ATTEMPT > 10));then
            error_exit "已经连续输入错误 ${ATTEMPT} 次，终止执行！"
        else
            echo "输入错误，请注意输入选项要求！"
            ((ATTEMPT++))
        fi
    done
    eval "$1=\$INPUT"
    return 1
}
# 初始化安装
# @command init_install $min_version $get_version_url $get_version_match [$get_version_rule]
# @param $min_version       安装脚本最低可安装版本号
# @param $get_version_url   安装脚本获取版本信息地址
# @param $get_version_match 安装脚本匹配版本信息正则
# @param $get_version_rule  安装脚本提取版本号正则
# return 1|0
init_install (){
    if (($# < 3));then
        error_exit "安装初始化参数错误"
    fi
    local INSTALL_VERSION_NAME=`echo "${INSTALL_NAME}_VERSION"|tr '[:lower:]' '[:upper:]'|sed -r 's/-/_/g'` VERSION_RULE=${4-'\d+(\.\d+){2}'}
    # 版本处理
    if [ -z "$ARGV_version" ] || [[ $ARGV_version == "new" ]]; then
        get_version $INSTALL_VERSION_NAME "$2" "$3" "$VERSION_RULE"
        if [ -z "$ARGV_version" ];then
            eval "echo $""$INSTALL_VERSION_NAME"
            exit 0;
        fi
    elif echo "$ARGV_version"|grep -qP "^${VERSION_RULE}$";then
        eval "$INSTALL_VERSION_NAME=\"$ARGV_version\""
    else
        error_exit "安装版本号参数格式错误：$ARGV_version"
    fi
    local INSTALL_VERSION=`eval "echo \$"$INSTALL_VERSION_NAME` INSTALL_VERSION_MIN=$1
    if [ -n "$INSTALL_VERSION_MIN" ] && if_version "$INSTALL_VERSION" "<" "$INSTALL_VERSION_MIN"; then
        error_exit "最小安装版本号: $INSTALL_VERSION_MIN ，当前是：$INSTALL_VERSION"
    fi
    if ps aux|grep -P "$INSTALL_NAME-install\.sh\s+(new|\d+\.\d+)"|grep -vqP "\s+$$\s+"; then
        error_exit "$INSTALL_NAME 已经在安装运行中"
    fi
    if [ -n "$ARGV_reset" ] && ! [[ "$ARGV_reset" =~ [0-3] ]];then
        error_exit "--reset 未知重装参数值：$ARGV_reset"
    fi
    # 安装目录
    INSTALL_PATH="$INSTALL_BASE_PATH/$INSTALL_NAME/"
    if [ -e "$INSTALL_PATH$INSTALL_VERSION/" ] && find "$INSTALL_PATH$INSTALL_VERSION/" -type f -executable|grep -qP "$INSTALL_NAME|bin";then
        echo "$INSTALL_NAME-$INSTALL_VERSION 安装目录不是空的: $INSTALL_PATH$INSTALL_VERSION/"
        if [ -z "$ARGV_reset" ];then
            exit 0
        else
            echo "强制重新安装：$INSTALL_NAME-$INSTALL_VERSION"
        fi
    fi
    echo "即将安装：$INSTALL_NAME-$INSTALL_VERSION"
    echo "工作目录: "`pwd`
    echo "安装目录: $INSTALL_PATH"
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
    if ! free -tg|grep -qi swap && if_version `free -tg|tail -1|grep -oP '\d+'|head -1` '<' '8';then
        dd if=/dev/zero of=/swap bs=1024 count=8M
        mkswap /swap
        chmod 0600 /swap
        swapon /swap
        echo "/swap swap swap sw 0 0" >> /etc/fstab
    fi
    return 0
}
INSTALL_NAME=${0%-*}
# 提取安装参数
CALL_INPUT_ARGVS=()
for ((INDEX=1;INDEX<=$#;INDEX++));do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=${@:$INDEX:1}
done
unset INDEX
parse_install_param CALL_INPUT_ARGVS
#基本安装目录
INSTALL_BASE_PATH=${ARGV_install_path-/usr/local}
if [ -z "$INSTALL_BASE_PATH" ] || [ ! -d "$INSTALL_BASE_PATH" ];then
    error_exit '安装根目录无效：'$INSTALL_BASE_PATH
fi
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
    error_exit '暂无支持包管理，请确认系统信息，目前只支持：yum、apt'
fi
# 网络基本工具安装
tools_install curl wget
# 获编译任务数
if [ -n "$DEFINE_INSTALL_TYPE" ];then
    case "$ARGV_make_jobs" in
        avg)
            HTREAD_NUM=$((`lscpu |grep '^CPU(s)'|grep -oP '\d+$'`/2+1))
        ;;
        max)
            HTREAD_NUM=`lscpu |grep '^CPU(s)'|grep -oP '\d+$'`
        ;;
        *)
            if printf '%s' "$ARGV_make_jobs"|grep -qP '^[1-9]\d*$';then
                HTREAD_NUM=$ARGV_make_jobs
            else
                error_exit '--make-jobs 必需是 >= 0 的正整数或者avg|max，现在是：'$ARGV_make_jobs
            fi
        ;;
    esac
else
    HTREAD_NUM=1
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
SHELL_WORK_PATH=$CURRENT_PATH
