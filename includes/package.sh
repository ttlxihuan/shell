#!/bin/bash
############################################################################
# 所有需要使用依赖包安装函数
# 依赖包分包管理器和编译两种安装方式
#   1、当包管理器里的版本达标时就以包管理器为准
#   2、当包管理器里的版本不达标时就下载编译安装
# 脚本处理公共文件，不能单独运行
############################################################################

# 获取已经安装合适版本的命令路径
# @command if_command_range_version $name $options [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
if_command_range_version(){
    local CURRENT_VERSION COMMAND_PATH COMMAND_AS="INSTALL_${1//-/_}_"
    # 获取所有已知版本
    for COMMAND_PATH in $(which -a $1); do
        # 命令失败不算有效命令
        if ! $COMMAND_PATH $2 1>/dev/null 2>/dev/null;then
            continue
        fi
        CURRENT_VERSION=$($COMMAND_PATH $2 2>&1|grep -oP '\d+(\.\d+)+'|head -n 1)
        if if_version_range "$CURRENT_VERSION" "$3" "$4";then
            eval "${COMMAND_AS}PATH=\$COMMAND_PATH; ${COMMAND_AS}VERSION=\$CURRENT_VERSION"
            return;
        fi
    done
    return 1;
}
# 判断命令是否存在多个不同版本
# @command if_many_version $name $option1 [$option2 ...]
# @param $name          命令名
# @param $option1       命令对比参数，一般以版本号对比
#                       如果不指定则有多个命令即算
# return 1|0
if_many_version(){
    if if_command "$1";then
        if [ $# = 1 ];then
            (( $(which -a "$1" 2>/dev/null|wc -l) > 1 ))
            return $?
        else
            local ITEM NEXT_VERSION PREV_VERSION
            while read ITEM;do
                NEXT_VERSION=$("$ITEM" ${@:2} 2>&1)
                if [ -z "$PREV_VERSION" ];then
                    PREV_VERSION=$NEXT_VERSION
                elif test "$NEXT_VERSION" != "$PREV_VERSION";then
                    return 0
                fi
            done <<EOF
$(which -a "$1" 2>/dev/null)
EOF
        fi
    fi
    return 1
}
# 判断版本大小
# @command if_version $version1 $if $version2
# @param $version1  版本号1
# @param $if        判断条件：>=,>,<=,<,==,!=
# @param $version2  版本号2
# return 1|0
if_version(){
    local RESULT VERSIONS=`echo -e "$1\n$3"|sort -Vrb`
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
# 补齐版本号
# @command repair_version $version_val $bit $add
# @param $version_val       当前版本号变量名
# @param $bit               版本号位数，默认是3位（比如: 10.11.1）
# @param $add               不够补位值，默认是 .0
# return 1|0
repair_version(){
    local CURRENT_VERSION=$(eval echo "\$$1") VERSION_COUNT=$((${2:-3} - 1))
    if ! echo "$CURRENT_VERSION"|grep -qP "^\d+(\D\d+)*";then
        error_exit "非法版本号: $CURRENT_VERSION"
    fi
    until echo "$CURRENT_VERSION"|grep -qP "^\d+(\D\d+){$VERSION_COUNT}";do
        CURRENT_VERSION="$CURRENT_VERSION${3:-.0}"
    done
    eval $1=\$CURRENT_VERSION
}
# 判断版本范围
# @command if_version_range $current_version $min_version $max_version
# @param $current_version   当前版本号
# @param $min_version       最低版本号
# @param $max_version       最高版本号
# return 1|0
if_version_range(){
    [ -n "$1" ] && ([ -z "$2" ] || if_version "$1" '>=' "$2") && ([ -z "$3" ] || if_version "$1" '<=' "$3");
}
# 获取库安装目录
# @command get_lib_install_path $name $path_val
# @param $name          库名
# @param $path_val      目录输入变量名
# return 1|0
get_lib_install_path(){
    eval $2="$(pkg-config --libs-only-L "$1" 2>/dev/null|grep -oP '/([^/]+/)+')"
}
# 判断库是否存在指定范围版本
# @command if_lib_range $name $min_version $max_version
# @param $name              库名
# @param $min_version       最低版本号
# @param $max_version       最高版本号
# return 1|0
if_lib_range(){
    # 安装pkg-config
    # pkg-config 是三方库管理工具，以.pc为后缀的文件来配置不同的三方头文件或库文件
    # 一般三方库需要有个以 -devel 为后缀的配置工具名安装后就会把以 .pc 为后缀的文件写到到 pkg-config 默认管理目录
    # 例如：安装openssl后需要再安装openssl-devel才可以使用 pkg-config 查看 openssl
    # 安装pkg-config
    if ! if_command pkg-config;then
        install_pkg_config
    fi
    if pkg-config --exists "$1";then
        local ITEM
        for ITEM in ">= $2" "<= $3";do
            if (( ${#ITEM} > 3 )) && ! pkg-config --cflags --libs "$1 $ITEM" >/dev/null;then
                return 1
            fi
        done
        return 0
    fi
    return 1
}
# 判断so库是否存在指定范围版本
# @command if_so_range $name $min_version $max_version
# @param $name              so库名
# @param $min_version       最低版本号
# @param $max_version       最高版本号
# return 1|0
if_so_range(){
    # ldconfig 是动态库管理工具，主要是通过配置文件 /etc/ld.so.conf 来管理动态库所在目录，记录系统可使用的 .so 库文件
    # ldconfig ldd 是在glibc库中包含，系统默认存在
    if ! if_command ldconfig;then
        error_exit "ldconfig 命令丢失，请确认glibc是否完整！"
    fi
    local SO_VERSION
    for SO_VERSION in $(ldconfig -v|grep -P "^\s*${1}[\-\.](\d+|so)"|grep -oP '\d+(\.\d+)+');do
        if if_version_range "$SO_VERSION" "$2" "$3";then
            return 0
        fi
    done
    return 1
}
# 包管理安装并指定最低安装版本和最高版本
# 如果最低版本达不到则不会进行包安装
# @command install_range_version $package_name [$min_version] [$max_version] 
# @param $package_name   要安装的包名
# @param $min_version   安装包最低版本
# @param $max_version   安装包最高版本
# return 1|0
install_range_version(){
    local PACKAGE_VERSION=$(package_manager_run info "$1"|grep -iP '^version\s*:'|grep -oP '\d+(\.\d+)+'|tail -n 1)
    if if_version_range "$PACKAGE_VERSION" "$2" "$3";then
        package_manager_run install "$1"
    else
        return 1
    fi
}
# 获取下载版本
# @command get_download_version $var_name $url $version_path_rule [$version_rule]
# @param $var_name          获取版本号变量名
# @param $url               获取版本号的HTML页面地址
# @param $version_path_rule 匹配版本号的正则规则（粗级匹配，获取所有版本号再排序提取最大的）
# @param $version_rule      提取版本号的正则规则（精准匹配，直接对应的版本号）
# return 1|0
get_download_version(){
    local VERSION VERSION_RULE="$4" ATTEMPT=1
    if [ -z "$4" ];then
        VERSION_RULE='\d+(\.\d+){1,2}'
    fi
    while true;do
        ((ATTEMPT++))
        VERSION=`wget -qO - --no-check-certificate "$2" 2>/dev/null|grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
        if [ -z "$VERSION" ];then
            VERSION=`curl -LkN "$2" 2>/dev/null|grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
        fi
        if [ -n "$VERSION" ];then
            break
        fi
        if ((ATTEMPT <= 3));then
            sleep ${ATTEMPT}s
            warn_msg "正在第 $ATTEMPT 次尝试获取版本号"
        else
            error_exit "已经尝试 $((ATTEMPT - 1)) 次尝试获取版本号失败 ，请确认是否可访问地址：$2"
        fi
    done
    eval "$1=\"$VERSION\""
    return 0
}
# 下载文件
# @command download_file $url $save_name
# @param $url           下载包的绝对URL地址
# @param $save_name     保存文件名，默认提取URL地址
# return 1|0
download_file(){
    FILE_NAME=${2:-$(basename "$1"|sed 's/[\?#].*$//')}
    chdir shell-install
    info_msg '下载保存目录：'`pwd`
    if [ ! -e "$FILE_NAME" ];then
        if ! wget --no-check-certificate -T 7200 -O "$FILE_NAME" "$1"; then
            tools_install curl
            curl -OLkN --connect-timeout 7200 -o "$FILE_NAME" "$1"
        fi
        if [ $? != '0' ];then
            local TEMP_FILENAME=`date +'%Y_%m_%d_%H_%M_%S'`_error_"$FILE_NAME"
            mv "$FILE_NAME" "$TEMP_FILENAME"
            warn_msg "下载失败: $1 ，保存文件名：$TEMP_FILENAME，终止继续执行"
        fi
        info_msg "下载文件成功，保存目录：`pwd`/$FILE_NAME"
    else
        info_msg "已经存在下载文件：$FILE_NAME"
    fi
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
    info_msg "下载并解压：$1"
    if [ -z "$DIR_NAME" ];then
        error_exit "下载目录找不到"
    fi
    chdir shell-install
    # 重新下载再安装
    if [ "$ARGV_download" = 'reset' -a -e "$FILE_NAME" ];then
        info_msg "删除下载文件重新下载：$FILE_NAME"
        rm -f $FILE_NAME
    fi
    if [[ "$ARGV_download" =~ ^(reset|again)$ ]] && [ -d "$DIR_NAME" ];then
        info_msg "删除解压目录重新解压：$DIR_NAME"
        rm -rf $DIR_NAME
    fi
    local DECOMPRESSION_INFO ATTEMPT=1
    while true;do
        ((ATTEMPT++))
        download_file $1 $FILE_NAME
        if [ -d "$DIR_NAME" ] && (( `ls -las $DIR_NAME|wc -l` > 2 ));then
            info_msg "解压目标目录 $DIR_NAME 已经存在有效文件，跳过解压操作"
            break
        else
            info_msg '解压下载文件：'$FILE_NAME
            case "$FILE_NAME" in
                *.gz|*.tar.gz|*.tgz)
                    DECOMPRESSION_INFO=$(tar -vzxf $FILE_NAME)
                ;;
                *.tar|*.tar.bz2)
                    DECOMPRESSION_INFO=$(tar -vxf $FILE_NAME)
                ;;
                *.zip)
                    if ! if_command unzip; then
                        package_manager_run install -UNZIP_PACKAGE_NAMES
                    fi
                    DECOMPRESSION_INFO=$(unzip $FILE_NAME)
                ;;
                *.tar.xz)
                    if ! if_command xz; then
                        package_manager_run install -XZ_PACKAGE_NAMES
                    fi
                    xz -d $FILE_NAME
                    TAR_FILE_NAME=${FILE_NAME%*.xz}
                    DECOMPRESSION_INFO=$(tar -vxf $TAR_FILE_NAME)
                ;;
                *.rpm|*.pem)
                    return 0
                ;;
                *)
                    error_exit "未知解压文件: $FILE_NAME"
                ;;
            esac
            if [ $? = '0' ];then
                info_msg "下载文件的sha256: "`sha256sum $FILE_NAME`
                break
            else
                warn_msg "解压 $FILE_NAME 失败，即将删除解压和下载产生文件及目录"
                [ -e "$FILE_NAME" ] && rm -f $FILE_NAME
                [ -d "$DIR_NAME" ] && rm -rf $DIR_NAME
                if ((ATTEMPT <= 3));then
                    warn_msg "正在第 $ATTEMPT 次尝试重新下载解压"
                else
                    error_exit "已经尝试 $((ATTEMPT - 1)) 次下载解压失败 ，请确认是否可访问下载地址：$1"
                fi
            fi
        fi
    done
    # 解压目录不存在，直接提取解压信息中最后一个目录
    if [ ! -d "$DIR_NAME" ];then
        # 提取解压目录
        DEC_DIR_NAME=$(printf '%s' "$DECOMPRESSION_INFO"|tail -n 1|grep -oP '([^/\s]+/)+'|awk -F '/' '{print $1}')
        if [ -d "$DEC_DIR_NAME" ];then
            mv "$DEC_DIR_NAME" "$DIR_NAME"
        fi
    fi
    if [ -d "$DIR_NAME" ];then
        info_msg "进入解压目录：$DIR_NAME"
        cd $DIR_NAME
    else
        if_error "解压目录找不到: $DIR_NAME"
    fi
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
        if [ "${ITEM:0:1}" = '?' ];then
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
    printf '%s' "${@:1}"|grep -qP "\--(($PREFIX)-)?($OPTION_NAME)(-dir(=\S+))?"
    return $?
}
# 是否存在待解析选项
# @command exist_options $item [$options ...]
# @param $item              需要判断的选项，禁用选项加!
# @param $options           有效选项集
# return 1|0
in_parse_options(){
    local ITEM
    for ITEM in ${@:2}; do
        if [ "$1" = "$ITEM" -o "$ITEM" = "?$1" ];then
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
    info_msg "make 编译安装"
    make -j $INSTALL_THREAD_NUM ${@:2} 2>&1
    if_error "make 编译失败"
    make install 2>&1
    if_error "make 安装失败"
    if [ -n "$1" ];then
        local PREFIX_PATH=$1
        if [[ "$1" =~ "=" ]];then
            PREFIX_PATH=${1#*=}
        fi
        # 添加库地址
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
    run_msg "./configure $* 2>&1"
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
    run_msg "make clean 2>&1"
    run_msg "$* 2>&1"
    if_error "cmake 编译安装失败"
    make_install "`echo "$*"|grep -oP "\-DCMAKE_INSTALL_PREFIX=\S+"`"
}
# 复制安装，即不需要编译直接复制
# @command copy_install [$user] [$prefix]
# @param $user              安装目录用户组
# @param $prefix            复制到安装目录，默认是：$INSTALL_PATH$INSTALL_VERSION
# return 1|0
copy_install(){
    local PREFIX_PATH=${2:-"$INSTALL_PATH$INSTALL_VERSION"}
    # 复制安装包
    mkdirs "$PREFIX_PATH"
    info_msg "复制所有文件到：$PREFIX_PATH"
    cp -R ./* "$PREFIX_PATH"
    if_error "复制安装文件失败"
    cd "$PREFIX_PATH"
    if [ -n "$1" ];then
        add_user "$1"
        chown -R "$1":"$1" ./*
    fi
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
        info_msg "添加环境变量${ENV_NAME}： $1"
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
    local RUN_FILE ITEM SET_ALLOW
    for RUN_FILE in `find $1 -maxdepth 1 -executable -type f`; do
        SET_ALLOW=$(($# < 2))
        for ITEM in ${@:2};do
            if [ ${RUN_FILE##*/} = $ITEM ];then
                SET_ALLOW=1
                break
            fi
        done
        if [ "$SET_ALLOW" = '1' ];then
            info_msg "添加执行文件连接：$RUN_FILE -> /usr/local/bin/$(basename $RUN_FILE)"
            ln -svf $RUN_FILE /usr/local/bin/${RUN_FILE##*/}
        fi
    done
}
# 添加库配置
# @command add_pkg_config $path
# @param $path      动态库目录
# return 1|0
add_pkg_config(){
    local PATH_INFO
    # 添加PKG配置
    for PATH_INFO in $(find $1 -name '*.pc' \( -path '*/lib/*' -o -path '*/lib64/*' \) -exec dirname {} \;|uniq);do
        add_path "$PATH_INFO" PKG_CONFIG_PATH
    done
}
# 添加动态库配置
# @command add_so_config $path
# @param $path      动态库目录
# return 1|0
add_so_config(){
    local PATH_INFO
    # 添加so配置
    for PATH_INFO in $(find $1 -maxdepth 4 \( -name '*.so' -o -name '*.so.*' \) \( -regex '.*/lib/[^/]+' -o -regex '.*/lib64/[^/]+' \) -exec dirname {} \;|uniq);do
        edit_conf /etc/ld.so.conf "$PATH_INFO" "$PATH_INFO"
    done
    # 缓存加载动态库
    ldconfig
}
# 创建用户（包含用户组、可执行shell、密码）
# @command add_user $username [$shell_name] [$password]
# @param $username      用户名
# @param $shell_name    当前用户可调用的shell脚本名，默认是/sbin/nologin
# @param $password      用户密码，不指定则不创建密码
# return 0
add_user(){
    if has_user "$1"; then
         info_msg "用户：$1 已经存在无需再创建";
    else
        local RUN_FILE='/sbin/nologin'
        if [ -n "$2" -a -e "$2" ];then
            RUN_FILE=$2
        fi
        useradd -M -U -s $RUN_FILE $1
        if_error "用户 $1 创建失败"
        if [ -n "$3" ];then
            if echo "$3"|passwd --stdin $1; then
                info_msg "创建用户：$1 密码: $3"
            fi
        fi
    fi
    return 0
}
# 安装结果，自动提取上个命令的返回值，=0 为成功，>0为失败
# @command print_install_result $name [$min_version [$max_version]]
# @param $name              安装包名
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
print_install_result(){
    local RESULT=$? PACKAGE_VERSION=''
    if [ -n "$2" ];then
        if [ -n "$3" ];then
            PACKAGE_VERSION=" $2 ~ $3"
        elif (($# > 2));then
            PACKAGE_VERSION=" >= $2"
        else
            PACKAGE_VERSION="-$2"
        fi
    elif [ -n "$3" ];then
        PACKAGE_VERSION=" <= $3"
    fi
    if [ $RESULT = '0' ];then
        info_msg "$1$PACKAGE_VERSION OK"
    else
        error_exit "安装 $1$PACKAGE_VERSION 失败，终止运行！"
    fi
}
# 网络基本工具安装
tools_install wget
install_curl
############################################################################
#########################       包管理安装部分      #########################
############################################################################
# 安装 gcc
# @command install_gcc [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_gcc(){
    if ! if_command_range_version gcc -v "$1" "$2";then
        install_range_version -GCC_C_PACKAGE_NAMES "$1" "$2" || run_install_shell gcc ${3:-"$1"};
        if_command_range_version gcc -v "$1" "$2"
    fi
    print_install_result gcc "$1" "$2"
    if [ "$(${INSTALL_gcc_PATH} -v 2>&1|grep -oP 'version\s+\d(\.\d)+'|tail -n 1)" != "$(gcc -v 2>&1|grep -oP 'version\s+\d(\.\d)+'|tail -n 1)" ];then
        add_local_run ${INSTALL_gcc_PATH%/*} gcc c++ g++ cpp
        if [ ! -e /usr/local/bin/gcc ];then
            ln -svf /usr/local/bin/gcc /usr/bin/cc
        fi
    fi
}
# 安装 python
# @command install_python [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_python(){
    if ([ -n "$1" ] && if_version "$1" '>=' '3.0.0') || ([ -n "$2" ] && if_version "$2" '>=' '3.0.0');then
        PYTHON_COMMAND_NAME='python3' PIP_NAME='pip3'
    elif ([ -n "$1" ] && if_version "$1" '>=' '2.0.0') || ([ -n "$2" ] && if_version "$2" '>=' '2.0.0');then
        PYTHON_COMMAND_NAME='python2' PIP_NAME='pip2'
    else
        PYTHON_COMMAND_NAME='python' PIP_NAME='pip'
    fi
    if ! if_command_range_version $PYTHON_COMMAND_NAME -V "$1" "$2";then
        run_install_shell python ${3:-"$1"}
        if_command_range_version $PYTHON_COMMAND_NAME -V "$1" "$2"
    fi
    print_install_result $PYTHON_COMMAND_NAME "$1" "$2"
}
# 安装 java
# @command install_java [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_java(){
    if ! if_command_range_version java -version "$1" "$2";then
        install_range_version -JAVA_PACKAGE_NAMES "$1" "$2"
        if_command_range_version java -version "$1" "$2"
    fi
    print_install_result java "$1" "$2"
}
# 安装 openssl
# @command install_openssl [$min_version [$max_version [$install_version [$not_compile]]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# @param $not_compile       只下载不编译
#                               为空下载后会编译安装
#                               非为空下载后不编译安装
#                               非为空且是 2 则如果不是安装在默认路径和仅单版则直接下载不编译安装
# return 1|0
install_openssl(){
    [ "$4" = 2 ] && (if_many_version openssl version || ! which -a openssl|grep -qP '^/usr(/local|/pkg)?/bin/openssl$')
    local USE_TYPE=$?
    if [ "$USE_TYPE" = 0 ] || ! if_lib_range openssl "$1" "$2" || ! if_command_range_version openssl version "$1" "$2";then
        if [ "$USE_TYPE" = 0 ] || ! install_range_version -OPENSSL_DEVEL_PACKAGE_NAMES "$1" "$2";then
            # 安装匹配版本
            local OPENSSL_VERSION=${3:-"$1"}
            if [ -z "$OPENSSL_VERSION" ];then
                # 没有指定版本就安装最新版本
                get_download_version OPENSSL_VERSION https://www.openssl.org/source/ 'openssl-\d+(\.\d+)+[a-z]?\.tar\.gz'
            fi
            info_msg "安装：openssl-$OPENSSL_VERSION"
            # 下载
            download_software https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz openssl-$OPENSSL_VERSION
            if [ -z "$4" ];then
                # 添加编译文件连接
                if [ ! -e './configure' ];then
                    cp ./config ./configure
                fi
                # 移除不要的组件
                package_manager_run remove openssl -OPENSSL_DEVEL_PACKAGE_NAMES
                # 编译安装
                configure_install --prefix=$INSTALL_BASE_PATH/openssl/$OPENSSL_VERSION
                add_so_config $INSTALL_BASE_PATH/openssl/$OPENSSL_VERSION
            else
                info_msg "跳过编译安装：openssl"
                print_install_result openssl "$1" "$2"
                return 1
            fi
        fi
        if_command_range_version openssl version "$1" "$2"
    fi
    print_install_result openssl "$1" "$2"
}
# 安装 curl
# @command install_curl [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_curl(){
    if ! if_lib_range libcurl "$1" "$2" || ! if_command_range_version curl -V "$1" "$2";then
        if ! install_range_version -CURL_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local CURL_VERSION=${3:-"$1"}
            if [ -z "$CURL_VERSION" ];then
                # 没有指定版本就安装最新版本
                get_download_version CURL_VERSION https://curl.se/download.html 'curl-\d+(\.\d+)+\.tar\.gz'
            fi
            info_msg "安装：curl-$CURL_VERSION"
            # 下载
            download_software https://curl.se/download/curl-$CURL_VERSION.tar.gz
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/curl/$CURL_VERSION --enable-libcurl-option --with-openssl
        fi
        if_command_range_version curl -V "$1" "$2"
    fi
    print_install_result curl "$1" "$2"
}
# 安装 sqlite
# @command install_sqlite [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_sqlite(){
    local SQLITE_COMMAND_NAME='sqlite'
    if ([ -n "$1" ] && if_version "$1" '>=' '3.0.0') || ([ -n "$2" ] && if_version "$2" '>=' '3.0.0');then
        SQLITE_COMMAND_NAME='sqlite3'
    fi
    if ! if_lib_range $SQLITE_COMMAND_NAME "$1" "$2" || ! if_command_range_version $SQLITE_COMMAND_NAME -version "$1" "$2";then
        if ! install_range_version -SQLITE_DEVEL_PACKAGE_NAMES "$1" "$2" && [ "$SQLITE_COMMAND_NAME" = 'sqlite3' ];then
            local SQLITE_VERSION SQLITE_PATH
            # 获取最新版
            get_download_version SQLITE_PATH https://www.sqlite.org/download.html '(\w+/)+sqlite-autoconf-\d+\.tar\.gz' '.*'
            SQLITE_VERSION=`echo $SQLITE_PATH|grep -oP '\d+\.tar\.gz$'|grep -oP '\d+'`

            info_msg "安装：$SQLITE_COMMAND_NAME-$SQLITE_VERSION"
            # 下载
            download_software https://www.sqlite.org/$SQLITE_PATH
            # 安装tcl
            package_manager_run install -TCL_PACKAGE_NAMES
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/sqlite/$SQLITE_VERSION --enable-shared
        fi
        if_command_range_version $SQLITE_COMMAND_NAME -version "$1" "$2"
    fi
    print_install_result $SQLITE_COMMAND_NAME "$1" "$2"
}
# 安装 zip
# @command install_zip [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_zip(){
    if ! if_lib_range libzip "$1" "$2";then
        if ! install_range_version -ZIP_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local LIBZIP_VERSION=${3:-"$1"}
            # 这里需要判断是否达到版本要求，达到了就不需要再安装了
            # libzip-1.4+ 版本需要使用cmake更高版本来安装，而cmake需要c++11安装相对麻烦
            # libzip-1.3+ 编译不能通过会提示 错误:‘LIBZIP_VERSION’未声明(在此函数内第一次使用)
            # 目前安装 1.2 版本可以通过编译
            if [ -z "$LIBZIP_VERSION" ];then
                # 没有指定版本就安装最新版本
                get_download_version LIBZIP_VERSION https://libzip.org/download/ 'libzip-\d+(\.\d+)+\.tar\.gz'
            fi
            info_msg "安装：libzip-$LIBZIP_VERSION"
            download_software https://libzip.org/download/libzip-$LIBZIP_VERSION.tar.gz
            # 暂存编译目录
            local ZIP_CONFIGURE_PATH=`pwd`
            # 删除旧包
            package_manager_run remove -ZIP_DEVEL_PACKAGE_NAMES
            # 安装zlib-dev
            install_zlib
            cd $ZIP_CONFIGURE_PATH
            if if_version "$LIBZIP_VERSION" '<' '1.4.0';then
                # 编译安装
                configure_install --prefix=$INSTALL_BASE_PATH/libzip/$LIBZIP_VERSION
            else
                install_cmake
                cmake_install $CMAKE_COMMAND_NAME -DCMAKE_INSTALL_PREFIX=$INSTALL_BASE_PATH/libzip/$LIBZIP_VERSION
            fi
        fi
        if_lib_range libzip "$1" "$2"
    fi
    print_install_result zip "$1" "$2"
}
# 安装 cmake
# @command install_cmake [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定为固定版本
# return 1|0
install_cmake(){
    CMAKE_COMMAND_NAME='cmake'
    if ([ -n "$1" ] && if_version "$1" '>=' '3.0.0') || ([ -n "$2" ] && if_version "$2" '>=' '3.0.0');then
        CMAKE_COMMAND_NAME='cmake3'
    fi
    if ! if_command_range_version $CMAKE_COMMAND_NAME -version "$1" "$2";then
        if ! install_range_version $CMAKE_COMMAND_NAME "$1" "$2";then
            local CMAKE_VERSION=${3}
            # get_download_version CMAKE_MAX_VERSION "https://cmake.org/files/" "v3\.\d+"
            # get_download_version CMAKE_VERSION "https://cmake.org/files/v$CMAKE_MAX_VERSION" "cmake-\d+\.\d+\.\d+"
            # 3.22.0以上版本文件路径不一样，暂时不安装太高版本
            if [ -z "$CMAKE_VERSION" ];then
                if [ "$CMAKE_COMMAND_NAME" = 'cmake3' ];then
                    CMAKE_VERSION='3.21.3'
                else
                    CMAKE_VERSION='2.8.12'
                fi
            fi
            download_software "https://cmake.org/files/v${CMAKE_VERSION%.*}/cmake-$CMAKE_VERSION.tar.gz"
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/$CMAKE_COMMAND_NAME/$CMAKE_VERSION
            ln -svf $INSTALL_BASE_PATH/$CMAKE_COMMAND_NAME/$CMAKE_VERSION/bin/cmake /usr/bin/$CMAKE_COMMAND_NAME
        fi
        if_command_range_version $CMAKE_COMMAND_NAME -version "$1" "$2"
    fi
    print_install_result $CMAKE_COMMAND_NAME "$1" "$2"
}
# 安装 pkg-config
# @command install_pkg_config [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_pkg_config(){
    if ! if_command_range_version pkg-config --version "$1" "$2";then
        if ! install_range_version -PKGCONFIG_PACKAGE_NAMES "$1" "$2";then
            local PKG_CONFIG_VERSION=${3:-"$1"}
            if [ -z "$PKG_CONFIG_VERSION" ];then
                # 没有指定版本就安装最新版本
                get_download_version PKG_CONFIG_VERSION https://pkg-config.freedesktop.org/releases/ 'pkg-config-\d+\.\d+\.tar\.gz'
            fi
            info_msg "安装 pkg-config-$PKG_CONFIG_VERSION"
            # 下载
            download_software https://pkg-config.freedesktop.org/releases/pkg-config-$PKG_CONFIG_VERSION.tar.gz
            # 编译安装
            configure_install --with-internal-glib --prefix="$INSTALL_BASE_PATH/pkg-config/$PKG_CONFIG_VERSION"
        fi
        if_command_range_version pkg-config --version "$1" "$2"
    fi
    print_install_result pkg-config "$1" "$2"
}
# 安装 ncurses
# @command install_ncurses [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_ncurses(){
    if ! if_lib_range ncurses "$1" "$2";then
        install_range_version -NCURSES_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_lib_range ncurses "$1" "$2"
    fi
    print_install_result ncurses "$1" "$2"
}
# 安装 pcre-config
# @command install_pcre_config [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_pcre_config(){
    if ! if_command_range_version pcre-config --version "$1" "$2";then
        install_range_version -PCRE_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_command_range_version pcre-config --version "$1" "$2"
    fi
    print_install_result pcre-config "$1" "$2"
}
# 安装 bzip2
# @command install_bzip2 [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_bzip2(){
    if ! if_command_range_version bzip2 --help "$1" "$2";then
        install_range_version -BZIP2_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_command_range_version bzip2 --help "$1" "$2"
    fi
    print_install_result bzip2 "$1" "$2"
}
# 安装 readline
# @command install_readline [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_readline(){
    if [ ! -d "/usr/include/readline/" ];then
        install_range_version -READLINE_DEVEL_PACKAGE_NAMES "$1" "$2"
        [ -d "/usr/include/readline/" ]
    fi
    print_install_result readline "$1" "$2"
}
# 安装 libpcre
# @command install_libpcre [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_libpcre(){
    if ! if_lib_range libpcre "$1" "$2";then
        install_range_version -PCRE_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_lib_range libpcre "$1" "$2"
    fi
    print_install_result libpcre "$1" "$2"
}
# 安装 libpcre2-8
# @command install_libpcre2_8 [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_libpcre2_8(){
    if ! if_lib_range libpcre2-8 "$1" "$2";then
        local LIBPCRE2_VERSION=${3:-"$1"}
        if [ -z "$LIBPCRE2_VERSION" ];then
            # 没有指定版本就安装最新版本
            # https://ftp.pcre.org/pub/pcre/ 已经停用无法
            get_download_version LIBPCRE2_VERSION https://github.com/PCRE2Project/pcre2/tags "pcre2-\d+\.\d+\.tar\.gz"
        fi
        info_msg '安装：libpcre-'$LIBPCRE2_VERSION
        # 下载
        download_software https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$LIBPCRE2_VERSION/pcre2-$LIBPCRE2_VERSION.tar.gz
        configure_install --prefix=$INSTALL_BASE_PATH/pcre2/$LIBPCRE2_VERSION
        if_lib_range libpcre2-8 "$1" "$2"
    fi
    print_install_result libpcre2-8 "$1" "$2"
}
# 安装 autoconf
# @command install_autoconf [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_autoconf(){
    if ! if_command_range_version autoconf --version "$1" "$2";then
        if ! install_range_version -AUTOCONF_PACKAGE_NAMES "$1" "$2";then
            # 版本过低需要安装高版本的
            package_manager_run remove autoconf
            local AUTOCONF_VERSION=${3:-"$1"}
            if [ -z "$AUTOCONF_VERSION" ];then
                # 获取最新版
                get_download_version AUTOCONF_VERSION http://ftp.gnu.org/gnu/autoconf/ 'autoconf-\d+(\.\d+)+\.tar\.gz'
            fi
            info_msg "安装：autoconf-$AUTOCONF_VERSION"
            # 下载
            download_software http://ftp.gnu.org/gnu/autoconf/autoconf-$AUTOCONF_VERSION.tar.gz
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/autoconf/$AUTOCONF_VERSION
        fi
        if_command_range_version autoconf --version "$1" "$2"
    fi
    print_install_result autoconf "$1" "$2"
}
# 安装 libtool
# @command install_libtool [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_libtool(){
    if ! if_command_range_version libtool --version "$1" "$2";then
        install_range_version -LIBTOOL_PACKAGE_NAMES "$1" "$2"
        if_command_range_version libtool --version "$1" "$2"
    fi
    print_install_result libtool "$1" "$2"
}
# 安装 libedit
# @command install_libedit [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_libedit(){
    if ! if_lib_range libedit "$1" "$2";then
        install_range_version -LIBEDIT_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_lib_range libedit "$1" "$2"
    fi
    print_install_result libedit "$1" "$2"
}
# 安装 m4
# @command install_m4 [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_m4(){
    if ! if_command_range_version m4 --version "$1" "$2";then
        install_range_version -M4_PACKAGE_NAMES "$1" "$2"
        if_command_range_version m4 --version "$1" "$2"
    fi
    print_install_result m4 "$1" "$2"
}
# 安装 zlib
# @command install_zlib [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_zlib(){
    if ! if_lib_range zlib "$1" "$2";then
        if ! install_range_version -ZLIB_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local ZLIB_VERSION=${3:-"$1"}
            if [ -z "$ZLIB_VERSION" ];then
                # 没有指定版本就安装最新版本
                get_download_version ZLIB_VERSION http://zlib.net/fossils "zlib-\d+(\.\d+)+\.tar\.gz"
            fi
            info_msg '安装：zlib-'$ZLIB_VERSION
            download_software http://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz
            configure_install --prefix=$INSTALL_BASE_PATH"/zlib/$ZLIB_VERSION"
        fi
        if_lib_range zlib "$1" "$2"
    fi
    print_install_result zlib "$1" "$2"
}
# 安装 libffi
# @command install_libffi [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_libffi(){
    if ! if_lib_range libffi "$1" "$2";then
        install_range_version -LIBFFI_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_lib_range libffi "$1" "$2"
    fi
    print_install_result libffi "$1" "$2"
}
# 安装 libxml2
# @command install_libxml2 [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_libxml2(){
    if ! if_lib_range libxml-2.0 "$1" "$2";then
        if ! install_range_version -LIBXML2_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local LIBXML2_VERSION=${3:-"$1"}
            if [ -z "$LIBXML2_VERSION" ];then
                # 获取最新版
                get_download_version LIBXML2_VERSION "ftp://xmlsoft.org/libxml2/" 'libxml2-sources-\d+\.\d+\.\d+\.tar\.gz'
            fi
            info_msg "安装：libxml2-$LIBXML2_VERSION"
            # 下载
            download_software ftp://xmlsoft.org/libxml2/libxml2-sources-$LIBXML2_VERSION.tar.gz libxml2-$LIBXML2_VERSION
            # 部分低版系统环境不好，所以直接禁止编译到python中
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/libxml2/$LIBXML2_VERSION --with-python=no
        fi
        if_lib_range libxml-2.0 "$1" "$2"
    fi
    print_install_result libxml2 "$1" "$2"
}
# 安装 gettext
# msgfmt命令在gettext包中
# @command install_gettext [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_gettext(){
    if ! if_command_range_version gettext --version "$1" "$2";then
        if ! install_range_version -GETTEXT_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local GETTEXT_VERSION=${3:-"$1"}
            if [ -z "$GETTEXT_VERSION" ];then
                # 获取最新版
                get_download_version GETTEXT_VERSION https://ftp.gnu.org/pub/gnu/gettext 'gettext-\d+(\.\d+){2}\.tar\.gz'
            fi
            info_msg "安装：gettext-$GETTEXT_VERSION"
            # 下载
            download_software https://ftp.gnu.org/pub/gnu/gettext/gettext-$GETTEXT_VERSION.tar.gz
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/gettext/$GETTEXT_VERSION
        fi
        if_command_range_version gettext --version "$1" "$2"
    fi
    print_install_result gettext "$1" "$2"
}
# 安装 libevent
# @command install_libevent [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_libevent(){
    if ! if_lib_range libevent "$1" "$2";then
        if ! install_range_version -LIBXML2_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local LIBEVENT_VERSION=${3:-"$1"}
            if [ -z "$LIBEVENT_VERSION" ];then
                # 获取最新版
                get_download_version LIBEVENT_VERSION https://libevent.org/ 'libevent-\d+(\.\d+)+-stable\.tar\.gz'
            fi
            info_msg "安装：libevent-$LIBEVENT_VERSION"
            # 下载
            download_software https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION-stable/libevent-$LIBEVENT_VERSION-stable.tar.gz libevent-$LIBEVENT_VERSION-stable
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/libevent/$LIBEVENT_VERSION
        fi
        if_lib_range libevent "$1" "$2"
    fi
    print_install_result libevent "$1" "$2"
}
# 安装 jemalloc
# @command install_jemalloc [$min_version [$max_version]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# return 1|0
install_jemalloc(){
    if ! if_command_range_version jemalloc.sh "$1" "$2";then
        install_range_version -JEMALLOC_DEVEL_PACKAGE_NAMES "$1" "$2"
        if_command_range_version jemalloc.sh "$1" "$2"
    fi
    print_install_result jemalloc "$1" "$2"
}
# 安装 iconv
# @command install_iconv [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_iconv(){
    if ! if_command_range_version iconv --version "$1" "$2";then
        local LIBICONV_VERSION=${3:-"$1"}
        if [ -z "$LIBICONV_VERSION" ];then
            # 获取最新版
            get_download_version LIBICONV_VERSION http://ftp.gnu.org/pub/gnu/libiconv/ 'libiconv-\d+\.\d+\.tar\.gz' '\d+\.\d+'
        fi
        info_msg "安装：libiconv-$LIBICONV_VERSION"
        # 下载
        download_software http://ftp.gnu.org/pub/gnu/libiconv/libiconv-$LIBICONV_VERSION.tar.gz
        # 编译安装
        configure_install --prefix=$INSTALL_BASE_PATH/libiconv/$LIBICONV_VERSION --enable-shared
        if_command_range_version iconv --version "$1" "$2"
    fi
    print_install_result iconv "$1" "$2"
}
# 安装 gmp
# @command install_gmp [$min_version [$max_version [$install_version]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# return 1|0
install_gmp(){
    if ! if_so_range libgmp "$1" "$2";then
        if ! install_range_version -GMP_DEVEL_PACKAGE_NAMES "$1" "$2";then
            local GMP_VERSION=${3:-"$1"}
            if [ -z "$GMP_VERSION" ];then
                # 获取最新版
                get_download_version GMP_VERSION https://gmplib.org/download/gmp/ 'gmp-\d+(\.\d+)+\.tar\.bz2'
            fi
            info_msg "安装：gmp-$GMP_VERSION"
            # 下载
            download_software https://gmplib.org/download/gmp/gmp-$GMP_VERSION.tar.bz2
            # 编译安装
            configure_install --prefix=$INSTALL_BASE_PATH/gmp/$GMP_VERSION --enable-shared
            add_so_config "$INSTALL_BASE_PATH/gmp/$GMP_VERSION"
        fi
        if_so_range libgmp "$1" "$2"
    fi
    print_install_result gmp "$1" "$2"
}
# 安装 apr
# @command install_apr  [$min_version [$max_version [$install_version [$not_compile]]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# @param $not_compile       只下载不编译
# return 1|0
install_apr(){
    if ! if_lib_range apr-1 "$1" "$2" || ! if_command_range_version apr-1-config --version "$1" "$2";then
        if ! install_range_version -APR_DEVEL_PACKAGE_NAMES "$1" "$2";then
            # 安装指定版本的apr
            local APR_VERSION VERSION_MATCH=`echo ${3:-"$1"}'.\d+.\d+.\d+'|awk -F '.' '{print $1,$2,$NF}' OFS='\\\.'`
            # 获取相近高版本
            get_download_version APR_VERSION https://archive.apache.org/dist/apr/ "apr-$VERSION_MATCH\.tar\.gz"
            info_msg "安装：apr-$APR_VERSION"
            # 下载
            download_software https://archive.apache.org/dist/apr/apr-$APR_VERSION.tar.gz
            if [ -z "$4" ];then
                # 安装
                configure_install --prefix="$INSTALL_BASE_PATH/apr/$APR_VERSION"
            else
                info_msg "跳过编译安装：apr"
                print_install_result apr "$1" "$2"
                return 1
            fi
        fi
        if_command_range_version apr-1-config --version "$1" "$2"
    fi
    print_install_result apr "$1" "$2"
}
# 安装 apr-util
# @command install_apr_util  [$min_version [$max_version [$install_version [$not_compile]]]]
# @param $min_version       安装最低版本
# @param $max_version       安装最高版本
# @param $install_version   没有合适版本时编译安装版本，不指定则安装最小版本
# @param $not_compile       只下载不编译
# return 1|0
install_apr_util(){
    if ! if_lib_range apr-util-1 "$1" "$2" || ! if_command_range_version apu-1-config --version "$1" "$2";then
        if ! install_range_version -APR_UTIL_DEVEL_PACKAGE_NAMES "$1" "$2";then
            # 安装指定版本的apu
            local APR_UTIL_VERSION VERSION_MATCH=`echo ${3:-"$1"}'.\d+.\d+.\d+'|awk -F '.' '{print $1,$2,$NF}' OFS='\\\.'`
            # 获取相近高版本
            get_download_version APR_UTIL_VERSION https://archive.apache.org/dist/apr/ "apr-util-$VERSION_MATCH\.tar\.gz"
            info_msg "安装：apr-util-$APR_UTIL_VERSION"
            # 下载
            download_software https://archive.apache.org/dist/apr/apr-util-$APR_UTIL_VERSION.tar.gz
            if [ -z "$4" ];then
                # 暂存编译目录
                APR_UTIL_CONFIGURE_PATH=`pwd`
                install_apr "$1" "$2" "$3"
                cd $APR_UTIL_CONFIGURE_PATH
                # 安装
                configure_install --prefix="$INSTALL_BASE_PATH/apr-util/$APR_UTIL_VERSION" --with-apr="$(dirname ${INSTALL_apr_1_config_PATH%/*})"
            else
                info_msg "跳过编译安装：apr-util"
                print_install_result apr-util "$1" "$2"
                return 1
            fi
        fi
        if_command_range_version apu-1-config --version "$1" "$2"
    fi
    print_install_result apr-util "$1" "$2"
}