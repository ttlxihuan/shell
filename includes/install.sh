#!/bin/bash
############################################################################
# 编译安装公共处理文件，所有安装脚本运行的核心文件
# 此脚本不可单独运行，需要在其它脚本中引用执行
############################################################################
if [ $(basename "$0") = $(basename "${BASH_SOURCE[0]}") ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 引用公共文件
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/basic.sh || exit
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
            if (( FREE_MAX_MEMORY <= 0 ));then
                warn_msg "当前系统可用物理内存不足1${USE_UNIT}，跳过配置处理"
            fi
        else
            # 指定配置处理
            FREE_MAX_MEMORY=${2/[BKMGT%]/}
            CURRENT_UNIT=${2:${#2}-2}
        fi
        if (( FREE_MAX_MEMORY > 0 )) && [ "$CURRENT_UNIT" != "$USE_UNIT" ];then
            local CURRENT_UNIT_VAL USE_UNIT_VAL UNIT_B=1 UNIT_K=1024 UNIT_M=1048576 UNIT_G=1073741824 UNIT_T=1099511627776
            eval 'CURRENT_UNIT_VAL=$UNIT_'$CURRENT_UNIT
            eval 'USE_UNIT_VAL=$UNIT_'$USE_UNIT
            FREE_MAX_MEMORY=$((FREE_MAX_MEMORY * CURRENT_UNIT_VAL / USE_UNIT_VAL))
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
    CURRENT_MEMORY=`cat /proc/meminfo|grep -P '^(MemTotal|SwapTotal):'|awk '{count+=$2} END{print count/1048576}'`
    # 剩余内存G
    # CURRENT_MEMORY=cat /proc/meminfo|grep -P '^(MemFree|SwapFree):'|awk '{count+=$2} END{print count/1048576}'
    math_compute DIFF_SIZE "$1 - $CURRENT_MEMORY"
    if ((DIFF_SIZE > 0)) && ([ "$ARGV_data_free" != 'ask' ] || ask_permit "内存最少 ${1}G，现在只有 ${CURRENT_MEMORY}G，是否增加虚拟内存 ${DIFF_SIZE}G：");then
        local BASE_PATH SWAP_PATH SWAP_NUM
        path_require $DIFF_SIZE / BASE_PATH;
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
        if [ "$ARGV_data_free" = 'save' -o "$ARGV_data_free" != 'ask' ] || ask_permit '虚拟内存交换是否写入系统配置用于重启后自动生效：';then
            # 写入配置文件，重启系统自动开启/swap目录交换空间
            if grep -qP "^$SWAP_PATH " /etc/fstab;then
                sed -i -r "s,^$SWAP_PATH .*$,$SWAP_PATH swap swap defaults 0 0," /etc/fstab
            else
                echo "$SWAP_PATH swap swap defaults 0 0" >> /etc/fstab
            fi
        fi
        info_msg "如果需要删除虚拟内存，先关闭交换区 ，然后删除文件，再去掉/etc/fstab文件中的配置行。"
        info_msg "可以执行命令：swapoff $SWAP_PATH && rm -f $SWAP_PATH && sed -i -r '/^${SWAP_PATH//\//\\/}\s+/d' /etc/fstab"
    fi
}
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
# 安装编译工作目录剩余空间要求
# @command work_path_require $min_size
# @param $min_size          安装编译工作目录最低磁盘剩余空间大小，G为单位
# return 1|0
work_path_require(){
    local BASE_PATH MIN_SIZE=0
    # 如果目录已经存在文件则需要获取当前目录的空间再剥除，这块操作比较耗时间
    if [ -d $SHELL_WROK_TEMP_PATH/$INSTALL_NAME ];then
        math_compute MIN_SIZE "$1-`du --max-depth=1 $SHELL_WROK_TEMP_PATH/$INSTALL_NAME|tail -1|awk '{print$1}'`/1048576"
    fi
    if ((MIN_SIZE > 0));then
        path_require $MIN_SIZE $SHELL_WROK_TEMP_PATH BASE_PATH;
        # 有匹配的工作目录，直接转移工作目录
        if [ -n "$BASE_PATH" -a "$BASE_PATH" != "$SHELL_WROK_TEMP_PATH" ];then
            mkdirs $BASE_PATH/shell-install
            SHELL_WROK_TEMP_PATH="$BASE_PATH/shell-install"
        fi
    fi
}
# 安装目录剩余空间要求
# @command install_path_require $min_size $path
# @param $min_size          安装目录最低磁盘剩余空间大小，G为单位
# @param $path              要判断的目录，默认安装根目录
# return 1|0
install_path_require(){
    if ((`df_awk ${2-$INSTALL_BASE_PATH}|awk '{print $4}'|tail -1` / 1048576 < $1 ));then
        info_msg "安装目录 $2 所在硬盘 `df_awk $2|awk '{print $1}'|tail -1` 剩余空间不足：${1}G ，无法进行安装！"
        if [ "$ARGV_data_free" = 'ignore' ];then
            warn_msg '忽略空间不足'
            return 0
        fi
        exit 1
    fi
}
# 获取指定目录对应挂载磁盘剩余空间要求
# @command path_require $min_size $path $path_name
# @param $min_size          安装脚本最低磁盘剩余空间大小，G为单位
# @param $path              要判断的目录
# @param $path_name         有空余的目录写入变量名
# return 1|0
path_require(){
    if ((`df_awk $2|awk '{print $4}'|tail -1` / 1048576 < $1 ));then
        info_msg "目录 $2 所在硬盘 `df_awk $2|awk '{print $1}'|tail -1` 剩余空间不足：${1}G"
        if [ "$ARGV_data_free" = 'ignore' ];then
            warn_msg '忽略空间不足'
        else
            search_free_path $3 $(($1 * 1048576))
        fi
    else
        eval "$3=\$2"
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
        if [ -n "$ITEM" ] && ([ "$ARGV_data_free" != 'ask' ] || ask_permit `printf "文件系统：%s 挂载目录：%s 可用空间：%s 是否选用：" $ITEM`);then
            ITEM=$(echo "$ITEM"|awk '{print $2}')
            eval "$1=\$ITEM"
            return 0
        fi
    done <<EOF
`df_awk -T|awk 'NR >1 && $5 > '$2' && $2 !~ "/*tmpfs/" && $4/$3 < 0.9 {$5=$5/1048576; print $1,$7,$5}'`
EOF
    error_exit "没有合适空间，终止执行！"
}
# 获取文件系统的信息
# 此命令主要是处理很长的存储名可能会换行导致awk处理错位
# 虚拟机常见，通过修正可以让存储名与对应的信息保持在一行中
# @command df_awk $options
# @param $options         选项参数
# return 1|0
df_awk(){
    df $@|awk '{if(NF==1){prev=$1}else{{print prev,$1,$2,$3,$4,$5,$6,$7}prev=""}}'
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
    VERSION=`curl -LkN $2 2>/dev/null| grep -oP "$3"|sort -Vrb|head -n 1|grep -oP "$VERSION_RULE"`
    if [ -z "$VERSION" ];then
        error_exit "获取版本数据失败: $2"
    fi
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
        if ! wget --no-check-certificate -T 7200 -O $FILE_NAME $1; then
            curl -OLkN --connect-timeout 7200 -o $FILE_NAME $1
        fi
        if [ $? != '0' ];then
            local TEMP_FILENAME=`date +'%Y_%m_%d_%H_%M_%S'`_error_$FILE_NAME
            mv $FILE_NAME $TEMP_FILENAME
            error_exit "下载失败: $1 ，保存文件名：$TEMP_FILENAME，终止继续执行"
        fi
        info_msg '下载文件成功，保存目录：'`pwd`/$FILE_NAME
    else
        info_msg '已经存在下载文件：'$FILE_NAME
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
    if [ "$ARGV_reset" = '3' -a -e "$FILE_NAME" ];then
        info_msg "删除下载文件重新下载：$FILE_NAME"
        rm -f $FILE_NAME
    fi
    if [[ "$ARGV_reset" =~ ^[2-3]$ ]] && [ -d "$DIR_NAME" ];then
        info_msg "删除解压目录重新解压：$DIR_NAME"
        rm -rf $DIR_NAME
    fi
    local ATTEMPT=1
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
            if [ $? = '0' ];then
                info_msg "下载文件的sha256: "`sha256sum $FILE_NAME`
                break
            else
                warn_msg "下载解压 $FILE_NAME 失败，即将删除解压和下载产生文件与目录"
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
    cd $DIR_NAME
    if_error "解压目录找不到: $DIR_NAME"
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
    run_msg "./configure $*"
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
    run_msg "$*"
    $* 2>&1
    if_error "cmake 编译安装失败"
    make_install "`echo "$*"|grep -oP "\-DCMAKE_INSTALL_PREFIX=\S+"`"
}
# 运行安装脚本
# @command run_install_shell $name $version_num [$other ...]
# @param $name              安装脚本名，比如：gcc
# @param $version_num       安装版本号
# @param $other             其它安装参数集
# return 1|0
run_install_shell (){
    local INSTALL_FILE_PATH
    find_project_file install "$1" INSTALL_FILE_PATH
    if [ -z "$2" ]; then
        error_exit "安装shell脚本必需指定的安装的版本号参数"
    fi
    run_msg "bash $INSTALL_FILE_PATH ${@:2} --data-free=${ARGV_data_free} --install-path=${INSTALL_BASE_PATH}"
    bash $INSTALL_FILE_PATH ${@:2} --data-free=${ARGV_data_free} --install-path=${INSTALL_BASE_PATH}
    if_error "安装shell脚本失败：$1"
    source /etc/profile
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
    if [ -n "`id $1 2>&1|grep "($1)"`" ]; then
         info_msg "用户：$1 已经存在无需再创建";
    else
        local RUN_FILE='/sbin/nologin'
        if [ -n "$2" -a -e "$2" ];then
            RUN_FILE=$2
        fi
        useradd -M -U -s $RUN_FILE $1
        if [ -n "$3" ];then
            if echo "$3"|passwd --stdin $1; then
                info_msg "创建用户：$1 密码: $3"
            fi
        fi
    fi
    return 0
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
            eval "echo $""$INSTALL_VERSION_NAME"
            exit 0;
        fi
    elif echo "$ARGU_version"|grep -qP "^${VERSION_RULE}$";then
        eval "$INSTALL_VERSION_NAME=\"$ARGU_version\""
    else
        error_exit "安装版本号参数格式错误：$ARGU_version"
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
        warn_msg "$INSTALL_NAME-$INSTALL_VERSION 安装目录不是空的: $INSTALL_PATH$INSTALL_VERSION/"
        if [ -z "$ARGV_reset" -o "$ARGV_reset" = '0' ];then
            exit 0
        else
            warn_msg "强制重新安装：$INSTALL_NAME-$INSTALL_VERSION"
        fi
    fi
    info_msg "即将安装：$INSTALL_NAME-$INSTALL_VERSION"
    info_msg "工作目录: $SHELL_WROK_TEMP_PATH"
    info_msg "安装目录: $INSTALL_PATH"
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
    return 0
}
# 获取安装名
INSTALL_NAME=$(basename "$0" '-install.sh')
# 安装通用参数信息配置
SHELL_RUN_DESCRIPTION="安装${INSTALL_NAME}脚本"
DEFINE_INSTALL_PARAMS="$DEFINE_INSTALL_PARAMS
[version]指定安装版本，不传则是获取最新稳定版本号
#传new安装最新版
#传指定版本号则安装指定版本
[--install-path='/usr/local'] 安装根目录，规则：安装根目录/软件名/版本号
#没有特殊要求建议安装根目录不设置到非系统所在硬盘目录下
[-r, --reset=0]重新安装，默认0
# 0 标准安装
# 1 重新安装
# 2 重新解压再安装
# 3 重新下载解压再安装
[--data-free=ask]数据空间不够用时处理
#   auto    自动选择，空间不足时搜索空间够用的硬盘使用
#   save    保存自动选择，主要是保存虚拟内存变化，保存重启仍然有效
#   ask     询问，可以选择性的允许空间处理
#   ignore  忽略，空间不足时不能保证安装成功
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
[-j, --make-jobs=avg]编译同时允许N个任务，可选值有 max|avg|number 
#   max 当前CPU数
#   avg 当前CPU半数+1
#   number 是指定的数值。
#任务多编译快且资源消耗也大（不建议超过CPU核数）
#当编译因进程被系统杀掉时可减少此值重试。
[-o, --options='']添加${DEFINE_INSTALL_TYPE}选项，使用前请核对选项信息。
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
parse_command_param DEFINE_INSTALL_PARAMS CALL_INPUT_ARGVS
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
if [ -z "$INSTALL_BASE_PATH" ] || [ ! -d "$INSTALL_BASE_PATH" ];then
    error_exit '安装根目录无效：'$INSTALL_BASE_PATH
fi
INSTALL_BASE_PATH=$(cd $INSTALL_BASE_PATH; pwd)
