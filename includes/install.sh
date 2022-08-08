#!/bin/bash
############################################################################
# 编译安装公共处理文件，所有安装脚本运行的核心文件
# 此脚本不可单独运行，需要在其它脚本中引用执行
#
# 编译死循环处理
#   1、make时会检查编译文件时间，有的时候文件时间不匹配导致编译无限死循环，需要在编译目录下修改下文件时间（可使用命令： find ./ -type f|xargs touch ），再进行编译（注意是configure所在目录）
#   2、清空编译目录再解压重新编译安装
#   3、使用单核编译
############################################################################
# 引用公共文件
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/basic.sh || exit
if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 随机生成密码
# @command random_password $password_val [$size] [$group]
# @param $password_val      生成密码写入变量名
# @param $size              密码长度，默认20
# @param $group             密码组合，默认包含：数字、字母大小写、~!@#$%^&*()_-=+,.;:?/\|
# return 1|0
random_password(){
    local PASSWORD_CHARS_STR='qwertyuiopasdfghjklzxcvbnm1234567890QWERTYUIOPASDFGHJKLZXCVBNM~!@#$%^&*_-=+,.;:?|'
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
# 解析使用密码
# @command parse_use_password $password_val [$size|$password] [$group]
# @param $password_val      生成密码写入变量名
# @param $size              生成密码长度：%num，比如生成10位密码：%10
# @param $password          指定密码
# @param $group             生成密码组合，默认全部类型
# return 1|0
parse_use_password(){
    if [[ "$2" =~ ^%[1-9][0-9]{0,2}$ ]];then
        random_password $1 ${2:1} $3
    else
        eval "$1=\$2"
    fi
}
# 解析使用内存
# @command parse_use_memory $var_name $ratio $unit
# @param $var_name          写入变量名
# @param $ratio             可用内存比率值，默认为 100
# @param $unit              转换内存单位，可选值：B、K、M、G，默认B
# return 1|0
parse_use_memory(){
    if ! [[ "$2" =~ ^([0-9]|[1-9][0-9]*)[BKMG%]?$ ]];then
        return 1
    fi
    local FREE_MAX_MEMORY USE_UNIT=${3:-B} CURRENT_UNIT='B'
    if [[ "$2" =~ ^0[BKMGT%]?$ ]];then
        # 不配置处理
        FREE_MAX_MEMORY=0
    else
        if [[ "$2" =~ ^[1-9][0-9]*%$ ]];then
            # 比率配置处理
            local RATIO_VALUE=${2//%/}
            # 内核3.14的上有MemAvailable
            if grep -q '^MemAvailable:' /proc/meminfo;then
                FREE_MAX_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|MemAvailable):'|awk '{count+=$2} END{print count*1024}')
            else
                FREE_MAX_MEMORY=$(cat /proc/meminfo|grep -P '^(MemFree|Buffers|Cached):'|awk '{count+=$2} END{print count*1024}')
            fi
            if (( FREE_MAX_MEMORY > 0 && RATIO_VALUE > 0 && RATIO_VALUE < 100 ));then
                FREE_MAX_MEMORY=$((FREE_MAX_MEMORY * RATIO_VALUE / 100))
            fi
        else
            # 指定配置处理
            FREE_MAX_MEMORY=${2/[BKMGT%]/}
            CURRENT_UNIT=${2:${#FREE_MAX_MEMORY}}
        fi
        if (( FREE_MAX_MEMORY > 0 )) && [ "$CURRENT_UNIT" != "$USE_UNIT" ];then
            size_switch FREE_MAX_MEMORY "$FREE_MAX_MEMORY" "$USE_UNIT"
        fi
        math_compute FREE_MAX_MEMORY "$FREE_MAX_MEMORY <= 0"
        if [ "$FREE_MAX_MEMORY" = '1' ];then
            warn_msg "当前系统可用物理内存不足1${USE_UNIT}，跳过配置处理"
        fi
    fi
    eval "$1=\$FREE_MAX_MEMORY"
}
# 当前安装内存空间要求，不够将添加虚拟内存扩充
# @command memory_require $min_size
# @param $min_size          安装脚本最低内存大小，G为单位
# return 1|0
memory_require(){
    local ASK_INPUT CURRENT_MEMORY DIFF_SIZE
    # 总内存G
    CURRENT_MEMORY=`cat /proc/meminfo|grep -P '^(MemTotal|SwapTotal):'|awk '{count+=$2} END{printf "%.2f", count/1048576}'`
    # 剩余内存G
    # CURRENT_MEMORY=cat /proc/meminfo|grep -P '^(MemFree|SwapFree):'|awk '{count+=$2} END{print count/1048576}'
    math_compute DIFF_SIZE "$1 - $CURRENT_MEMORY"
    if ((DIFF_SIZE > 0));then
        warn_msg "内存不足：${1}G，当前只有：${CURRENT_MEMORY}G"
        if [ "$ARGV_memory_space" = 'ignore' ] || ([ "$ARGV_memory_space" = 'ask' ] && ! ask_permit "是否增加虚拟内存 ${DIFF_SIZE}G ？");then
            warn_msg '忽略内存不足，继续安装'
            return
        elif [ "$ARGV_memory_space" = 'stop' ];then
            error_exit '内存空间不足，退出安装'
        fi
        local SWAP_PATH SWAP_NUM BASE_PATH='/'
        info_msg '即将在根目录下创建虚拟内存空间'
        path_require $BASE_PATH $DIFF_SIZE;
        SWAP_PATH=${BASE_PATH%/*}/swap
        SWAP_NUM=$(find $BASE_PATH -maxdepth 1 -name swap*|grep -oP 'swap\d+$'|sort -r|head -1|grep -oP '\d+$')
        if [ -n "$SWAP_NUM" ];then
            SWAP_PATH=$SWAP_PATH$(( SWAP_NUM + 1))
        elif [ -e "$SWAP_PATH" ];then
            SWAP_PATH=${SWAP_PATH}1
        fi
        info_msg '创建虚拟内存交换区：'$SWAP_PATH
        # 创建一个空文件区，并以每块bs字节重复写count次数且全部写0，主要是为防止内存溢出或越权访问到异常数据
        dd if=/dev/zero of=$SWAP_PATH bs=1024 count=${DIFF_SIZE}M
        # 将/swap目录设置为交换区
        mkswap $SWAP_PATH
        # 修改此目录权限
        chmod 0600 $SWAP_PATH
        # 开启/swap目录交换空间，开启后系统将建立虚拟内存，大小为 bs * count
        swapon $SWAP_PATH
        if [ "$ARGV_memory_space" != 'ask' ] || ask_permit '虚拟内存是否写入/etc/fstab文件用于重启后自动生效？';then
            # 写入配置文件，重启系统自动开启/swap目录交换空间
            if grep -qP "^$SWAP_PATH " /etc/fstab;then
                sed -i -r "s,^$SWAP_PATH .*$,$SWAP_PATH swap swap defaults 0 0," /etc/fstab
            else
                echo "$SWAP_PATH swap swap defaults 0 0" >> /etc/fstab
            fi
        else
            warn_msg '虚拟内存未写入/etc/fstab文件中，重启不会自动加载此虚拟内存'
        fi
        info_msg "如果需要删除虚拟内存，先关闭交换区 ，然后删除文件，再去掉/etc/fstab文件中的配置行。"
        info_msg "可以执行命令：swapoff $SWAP_PATH && rm -f $SWAP_PATH && sed -i -r '/^${SWAP_PATH//\//\\/}\s+/d' /etc/fstab"
    else
        info_msg "内存容量：${CURRENT_MEMORY}G"
    fi
}
# 获取指定目录对应挂载磁盘剩余空间要求
# @command path_require $min_size $path $path_name
# @param $path              判断的目录
# @param $min_size          要求目录挂载分区剩余空间G为单位
# @param $path_name         允许空间不足自动搜索空间够用目录，且将最终目录写入变量中
# return 1|0
path_require(){
    local PART_INFO=(`df_awk -k $1|awk '{print $1,$4}'|tail -1`)
    if ((${PART_INFO[1]} / 1048576 < $2 ));then
        warn_msg "目录 $1 所在分区 ${PART_INFO[0]} 剩余空间不足：${2}G"
        if [ "$ARGV_disk_space" = 'ignore' ] || ([ "$ARGV_disk_space" = 'ask' ] && ask_permit "是否继续安装？");then
            warn_msg '忽略磁盘空间不足，继续安装'
        else
            error_exit '磁盘空间不足，退出安装'
        fi
    else
        info_msg "目录 $1 所在分区 ${PART_INFO[0]} 可用空间：$((${PART_INFO[1]} / 1048576))G"
    fi
}
# 安装存储空间要求，单位G
# @command install_storage_require $work_path_size $install_path_size $memory_size
# @param $work_path_size       安装编译暂时目录空间要求
# @param $install_path_size    安装目标目录空间要求
# @param $memory_size          安装编译内存要求
# return 1|0
install_storage_require(){
    local EXIST_SIZE=0 MIN_SIZE=$1
    info_msg "安装下载暂时目录空间要求：${1}G"
    # 目标目录已经存在文件则自动减少要求空间
    if [ -d $SHELL_WROK_TEMP_PATH/shell-install ];then
        EXIST_SIZE=$(find $SHELL_WROK_TEMP_PATH/shell-install -maxdepth 1 -name $INSTALL_NAME-* -name *$INSTALL_VERSION* -exec du -k --max-depth=1 {} \;|awk 'BEGIN{total=0}{total+=$1}END{if(total>1048576){printf "%.0f",total/1048576}else{print 0}}')
        MIN_SIZE=$(($1 - EXIST_SIZE))
        info_msg "安装下载暂时目录已经存在相关文件或目录占用：${EXIST_SIZE}G，扣除后要求：${MIN_SIZE}G"
    fi
    #编译安装临时目录
    path_require $SHELL_WROK_TEMP_PATH $MIN_SIZE
    MIN_SIZE=$2
    info_msg "安装目录空间要求：${2}G"
    # 目标目录已经存在文件则自动减少要求空间
    if [ -d $INSTALL_BASE_PATH/$INSTALL_NAME ];then
        EXIST_SIZE=$(find $INSTALL_BASE_PATH/$INSTALL_NAME -maxdepth 1 -name $INSTALL_VERSION -exec du -k --max-depth=1 {} \;|awk 'BEGIN{total=0}{total+=$1}END{if(total>1048576){printf "%.0f",total/1048576}else{print 0}}')
        MIN_SIZE=$(($1 - EXIST_SIZE))
        info_msg "安装目录空间已经存在相关文件或目录占用：${EXIST_SIZE}G，扣除后要求：${MIN_SIZE}G"
    fi
    #安装目录
    path_require $INSTALL_BASE_PATH $MIN_SIZE
    #内存
    info_msg "内存空间要求：${3}G"
    memory_require $3
}
# 获取版本
# @command get_version $var_name $url $version_path_rule [$version_rule]
# @param $var_name          获取版本号变量名
# @param $url               获取版本号的HTML页面地址
# @param $version_path_rule 匹配版本号的正则规则（粗级匹配，获取所有版本号再排序提取最大的）
# @param $version_rule      提取版本号的正则规则（精准匹配，直接对应的版本号）
# return 1|0
get_version(){
    local VERSION VERSION_RULE="$4" ATTEMPT=1
    if [ -z "$4" ];then
        VERSION_RULE='\d+(\.\d+){1,2}'
    fi
    while true;do
        ((ATTEMPT++))
        VERSION=`curl -LkN "$2" 2>/dev/null|grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
        if [ -n "$VERSION" ];then
            break
        fi
        if ((ATTEMPT <= 3));then
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
    FILE_NAME=${2-`base $1|sed 's/[\?#].*$//'`}
    chdir shell-install
    info_msg '下载保存目录：'`pwd`
    if [ ! -e "$FILE_NAME" ];then
        if ! wget --no-check-certificate -T 7200 -O "$FILE_NAME" "$1"; then
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
                        packge_manager_run install -UNZIP_PACKGE_NAMES
                    fi
                    DECOMPRESSION_INFO=$(unzip $FILE_NAME)
                ;;
                *.tar.xz)
                    if ! if_command xz; then
                        packge_manager_run install -XZ_PACKGE_NAMES
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
    printf '%s' "${@:1}"|grep -qP "\--(($PREFIX)-)?($OPTION_NAME)(-dir(=\S+))?"
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
    local RUN_FILE NUM SET_ALLOW
    for RUN_FILE in `find $1 -executable`; do
        if (($# > 1));then
            SET_ALLOW=0
            for ((NUM=1;NUM<=$#;NUM++));do
                if [[ ${RUN_FILE##*/} == ${@:$NUM:1} ]];then
                    SET_ALLOW=1
                    break
                fi
            done
        else
            SET_ALLOW=1
        fi
        if (($SET_ALLOW > 0));then
            info_msg "添加执行文件连接：$RUN_FILE -> /usr/local/bin/$(basename $RUN_FILE)"
            ln -svf $RUN_FILE /usr/local/bin/${RUN_FILE##*/}
        fi
    done
}
# 添加动态库
# @command add_pkg_config $path
# @param $path      动态库目录
# return 1|0
add_pkg_config(){
    # 设置了环境变量
    local PATH_INFO
    for PATH_INFO in $(find $1 -path '*/lib*' -name '*.pc' -exec dirname {} \;|uniq);do
        add_path $PATH_INFO PKG_CONFIG_PATH
    done
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
# 服务配置键名
# 配置服务名
SERVICES_CONFIG_NAME=0
# 启动服务命令，必需指定否则不能启动服务
SERVICES_CONFIG_START_RUN=1
# 重启服务命令，可选，不指定会调用停止再启动
SERVICES_CONFIG_RESTART_RUN=2
# 服务对应的pid文件，当没有指定stop-run和status-run时必选否则无法获取状态或停止操作
SERVICES_CONFIG_PID_FILE=3
# 获取pid命令，属于动态提取pid，功能与pid-file一样，指定pid-file时此配置无效
SERVICES_CONFIG_PID_RUN=4
# 服务停止命令，如果未配置将取pid进行杀进程
SERVICES_CONFIG_STOP_RUN=5
# 获取服务状态命令，如果未配置将判断pid进程是否存在
SERVICES_CONFIG_STATUS_RUN=6
# 获取服务状态命令，如果未配置将判断pid进程是否存在
SERVICES_CONFIG_USER=7
# 获取服务状态运行根目录，默认为当前安装目录
SERVICES_CONFIG_BASE_PATH=8
# 服务配置键名对应位置
SERVICES_CONFIG_KEYS=('info' 'start-run' 'restart-run' 'pid-file' 'pid-run' 'stop-run' 'status-run' 'user' 'base-path')
# 添加安装的服务
# @command add_service $config_name
# @param  $config_name          配置数组名
# return 1|0
add_service(){
    local SERVICES_TOOL CONFIG_FILE CONFIG_NAME SERVICE_RUN SERVICE_BASE_PATH BLOCK_NAME EXIST_CONF=0
    eval CONFIG_NAME="\${$1[$SERVICES_CONFIG_NAME]}"
    eval SERVICE_RUN="\${$1[$SERVICES_CONFIG_START_RUN]}"
    eval "$1[$SERVICES_CONFIG_BASE_PATH]=\${$1[$SERVICES_CONFIG_BASE_PATH]-\"\$INSTALL_PATH\$INSTALL_VERSION\"}"
    if [ -z "$CONFIG_NAME" ];then
        CONFIG_NAME="$INSTALL_NAME-$INSTALL_VERSION"
        eval $1[$SERVICES_CONFIG_NAME]="$CONFIG_NAME"
    fi
    if [ -z "$SERVICE_RUN" ];then
        error_exit "服务启动命令未指定！"
    fi
    find_project_file etc services CONFIG_FILE
    # 只判断块名是否存在，不存在就增加，存在就跳过
    while read BLOCK_NAME;do
        if [ "$BLOCK_NAME" = "$CONFIG_NAME" ];then
            warn_msg "服务管理已经配置 $CONFIG_NAME ，跳过写配置处理！"
            EXIST_CONF=1
            break
        fi
    done <<EOF
$(grep -nP '^\s*\[.+\]' $CONFIG_FILE|grep -oP '(^\d+)|([~!@#\$%\^\&\*_\-\+/|:\.\?[:alnum:]]+)')
EOF
    # 锁定配置文件
    
    # 写服务配置
    if [ "$EXIST_CONF" = '0' ];then
        echo "" >> $CONFIG_FILE
        echo "[$CONFIG_NAME]" >> $CONFIG_FILE
        local CONFIG_VAL INDEX
        for ((INDEX=0;INDEX<${#SERVICES_CONFIG_KEYS[@]};INDEX++));do
            eval CONFIG_VAL="\${$1[$INDEX]}"
            if [ -n "$CONFIG_VAL" ];then
                echo "${SERVICES_CONFIG_KEYS[$INDEX]}=$CONFIG_VAL" >> $CONFIG_FILE
            fi
        done
    fi
    # 搜索服务管理脚本
    find_project_file tool services SERVICES_TOOL
    # 启动服务
    run_msg bash $SERVICES_TOOL start "$CONFIG_NAME"
}
# 初始化安装
# @command init_install $min_version $get_version_url $get_version_match [$get_version_rule]
# @param $min_version       安装脚本最低可安装版本号
# @param $get_version_url   安装脚本获取版本信息地址
# @param $get_version_match 安装脚本匹配版本信息正则
# @param $get_version_rule  安装脚本提取版本号正则
# return 1|0
init_install(){
    if [ -z "$INSTALL_NAME" ];then
        error_exit "获取安装名失败"
    fi
    if (($# < 3));then
        error_exit "安装初始化参数错误"
    fi
    local INSTALL_VERSION_NAME=`echo "${INSTALL_NAME}_VERSION"|tr '[:lower:]' '[:upper:]'|sed -r 's/-/_/g'` VERSION_RULE=${4-'\d+(\.\d+){2}'}
    # 版本处理
    if [ -z "$ARGU_version" ] || [[ $ARGU_version == "new" ]]; then
        get_version $INSTALL_VERSION_NAME "$2" "$3" "$VERSION_RULE"
        if [ -z "$ARGU_version" ];then
            eval echo "最新稳定版本：\$$INSTALL_VERSION_NAME"
            exit 0;
        fi
    elif echo "$ARGU_version"|grep -qP "^${VERSION_RULE}$";then
        eval "$INSTALL_VERSION_NAME=\"$ARGU_version\""
    else
        error_exit "安装版本号参数格式错误：$ARGU_version"
    fi
    INSTALL_VERSION=$(eval echo "\$$INSTALL_VERSION_NAME")
    local INSTALL_VERSION_MIN=$1
    if [ -n "$INSTALL_VERSION_MIN" ] && if_version "$INSTALL_VERSION" "<" "$INSTALL_VERSION_MIN"; then
        error_exit "最小安装版本号: $INSTALL_VERSION_MIN ，当前是：$INSTALL_VERSION"
    fi
    if has_run_shell "$INSTALL_NAME-install" ;then
        error_exit "$INSTALL_NAME 在安装运行中"
    fi
    # 安装目录
    INSTALL_PATH="$INSTALL_BASE_PATH/$INSTALL_NAME/"
    info_msg "即将安装：$INSTALL_NAME-$INSTALL_VERSION"
    info_msg "工作目录: $SHELL_WROK_TEMP_PATH"
    info_msg "安装目录: $INSTALL_PATH"
    if [ -e "$INSTALL_PATH$INSTALL_VERSION/" ] && find "$INSTALL_PATH$INSTALL_VERSION/" -type f -executable|grep -qP "$INSTALL_NAME|bin";then
        if [ "$ARGV_action" = 'install' ];then
            error_exit "$INSTALL_PATH$INSTALL_VERSION/ 安装目录不是空的，终止安装"
        else
            warn_msg "$INSTALL_PATH$INSTALL_VERSION/ 安装目录不是空的，即将强制重新安装：$INSTALL_NAME-$INSTALL_VERSION"
        fi
    fi
    if [ -n "$DEFINE_INSTALL_TYPE" ];then
        # 有编译类型安装编译所需基本工具
        tools_install gcc make
        if ! if_command ntpdate; then
            packge_manager_run install ntpdate 2> /dev/null
        fi
        if ! if_command ntpdate; then
            # 更新系统时间
            ntpdate -u ntp.api.bz 2>&1 &>/dev/null &
        fi
    fi
    # 加载环境配置
    source /etc/profile
    return 0
}
# 获取安装名
INSTALL_NAME=$(basename "$0" '-install.sh')
# 安装通用参数信息配置
SHELL_RUN_DESCRIPTION="安装${INSTALL_NAME}脚本"
DEFINE_INSTALL_PARAMS="$DEFINE_INSTALL_PARAMS
[version, {regexp:'^(new|[0-9]{1,}(.[0-9]{1,}){1,4})$'}]指定安装版本，不传则是获取最新稳定版本号
#传new安装最新版
#传指定版本号则安装指定版本
[--install-path='/usr/local', {required_with:ARGU_version|path}]安装根目录，规则：安装根目录/软件名/版本号
#没有特殊要求建议安装根目录不设置到非系统所在硬盘目录下
[-A, --action='install', {required|in:install,reinstall}]处理类型，默认 install
#   install     标准安装
#   reinstall   重新安装（覆盖安装）
[-D, --download='continue', {required|in:continue,reset,again}]下载方式，默认 continue
#   continue    延续下载，已经下载或解压跳过
#   again       重新解压并延续下载，
#   reset       重新解压和下载
[--disk-space=ask, {required|in:ask,ignore,stop}]安装磁盘分区空间不够用时处理
#   ask     空间不足时询问操作
#   ignore  忽略空间不足
#   stop    空间不足停止安装
[--memory-space=ask, {required|in:swap,ask,ignore,stop}]内存空间不够用时处理
#   swap    空间不足直接创建虚拟内存
#   ask     空间不足时询问操作
#   ignore  忽略空间不足
#   stop    空间不足停止安装
#数据空间包括编译目录硬盘和内存大概最少剩余空间
#处理操作有：编译目录转移，自动添加虚拟内存等
"
SHELL_RUN_HELP="安装脚本一般使用方式:
获取最新稳定安装版本号:
    bash ${INSTALL_NAME}-install.sh

安装最新稳定版本${INSTALL_NAME}:
    bash ${INSTALL_NAME}-install.sh new

安装指定版本${INSTALL_NAME}:
    bash ${INSTALL_NAME}-install.sh 1.1.1
"
if [ -n "$DEFINE_INSTALL_TYPE" ];then
    DEFINE_INSTALL_PARAMS="$DEFINE_INSTALL_PARAMS
[-j, --make-jobs=avg, {required|in:max,avg,number}]编译同时允许N个任务，可选值有 max|avg|number 
#   max 当前CPU数
#   avg 当前CPU半数+1
#   number 是指定的数值。
#任务多编译快且资源消耗也大（不建议超过CPU核数）
#当编译因进程被系统杀掉时可减少此值重试。
[-o, --options=]添加${DEFINE_INSTALL_TYPE}选项，使用前请核对选项信息。
"
if [ "$DEFINE_INSTALL_TYPE" = 'configure' ];then
    DEFINE_INSTALL_PARAMS="$DEFINE_INSTALL_PARAMS
#增加${DEFINE_INSTALL_TYPE}选项，支持以下三种方式传参：
#   1、原样选项 --xx 、-xx 或 ?--xx 、?-xx
#   2、启用选项 xx 或 ?xx 解析后是 --enable-xx 或 --with-xx 
#   3、禁用选项 !xx 或 ?!xx 解析后是 --disable-xx
#选项前面的?是在编译选项时会查找选项是否存在，如果不存在则丢弃，存在则附加
#选项前面的!是禁用某个选项，解析后会存在该选项则附加
#选项多数有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
    SHELL_RUN_HELP=$SHELL_RUN_HELP"
安装最新稳定版本${INSTALL_NAME}且指定安装选项:
    bash ${INSTALL_NAME}-install.sh new --options=\"?ext1 ext2\"
"
elif [ -n "$DEFINE_INSTALL_TYPE" ];then
    DEFINE_INSTALL_PARAMS="$DEFINE_INSTALL_PARAMS
#增加${DEFINE_INSTALL_TYPE}原样选项，选项按${DEFINE_INSTALL_TYPE}标准即可。
#选项部分有依赖要求，在增选项前需要确认依赖是否满足，否则容易造成安装失败。
"
    SHELL_RUN_HELP=$SHELL_RUN_HELP"
安装最新稳定版本${INSTALL_NAME}且指定安装选项:
    bash ${INSTALL_NAME}-install.sh new --options=\"opt1 opt2\"
"
    fi
fi
SHELL_RUN_HELP=$SHELL_RUN_HELP"
1、安装脚本会在脚本所在临时目录创建安装目录，此目录用于下载和编译安装包。
2、当后续再次安装相同版本时，已经存在的安装包将不再下载而是直接使用。
3、如果安装多台服务器可直接复制安装目录及安装包，这样就不会再下载而是直接安装处理。也可以使用远程安装工具脚本。
4、安装时会自动安装与之匹配的各种依赖包，但并未穷尽处理，尤其安装新版本或增加安装选项时需要格外注意安装结果。
5、安装后并未删除编译文件，需要手动删除。
"
# 解析安装参数
parse_shell_param DEFINE_INSTALL_PARAMS CALL_INPUT_ARGVS
# 常规参数验证
if ! [[ "$ARGV_memory_space" =~ ^(swap|ask|ignore|stop)$ ]];then
    error_exit '--memory-space 传入参数错误，如果不了解参数要求可通过 -h 查看'
fi
if ! [[ "$ARGV_disk_space" =~ ^(ask|ignore|stop)$ ]];then
    error_exit '--memory-space 传入参数错误，如果不了解参数要求可通过 -h 查看'
fi
# 获取总线程数
TOTAL_THREAD_NUM=`lscpu |grep '^CPU(s)'|grep -oP '\d+$'`
# 获取编译任务数
if [ -n "$DEFINE_INSTALL_TYPE" ];then
    case "$ARGV_make_jobs" in
        avg)
            INSTALL_THREAD_NUM=$((TOTAL_THREAD_NUM/2+1))
        ;;
        max)
            INSTALL_THREAD_NUM=$TOTAL_THREAD_NUM
        ;;
        *)
            if printf '%s' "$ARGV_make_jobs"|grep -qP '^[1-9]\d*$';then
                INSTALL_THREAD_NUM=$ARGV_make_jobs
            else
                error_exit '--make-jobs 必需是 >= 0 的正整数或者avg|max，现在是：'$ARGV_make_jobs
            fi
        ;;
    esac
else
    INSTALL_THREAD_NUM=1
fi
# 网络基本工具安装
tools_install curl wget
#基本安装目录
INSTALL_BASE_PATH=${ARGV_install_path-/usr/local}
safe_realpath INSTALL_BASE_PATH
if [ -z "$INSTALL_BASE_PATH" ] || [ ! -d "$INSTALL_BASE_PATH" ];then
    error_exit '安装根目录无效：'$INSTALL_BASE_PATH
fi
# 安装根目录
INSTALL_BASE_PATH=$(cd $INSTALL_BASE_PATH; pwd)
