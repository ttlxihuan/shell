#!/bin/bash
# 自动分区和挂载工具
# 1、自动分区
# 2、自动格式化
# 3、自动挂载并写入/etc/fstab配置文件中
#
# 了解语法：
# bash disk.sh -h

# 解析命令参数
# 命令参数解析成功后，将写入参数名规则：ARGV_参数全名（横线转换为下划线，缩写选项使用标准选项代替，使用时注意参数名的大小写不变）
# @command parse_command_param
# return 1|0
parse_command_param() {
    # 解析匹配传入参数
    local NAME INDEX ITEM ARG_NAME ARG_NUM VALUE OPTIONS_TEMP NAME_TEMP VALUE_TEMP ARGUMENTS_INDEX=0 ARG_SIZE=${#CALL_INPUT_ARGVS[@]}
    for ((ARG_NUM=0; ARG_NUM < $ARG_SIZE; ARG_NUM++)); do
        ITEM=${CALL_INPUT_ARGVS[$ARG_NUM]}
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
                            VALUE=${CALL_INPUT_ARGVS[$ARG_NUM]}
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
}
# 输出错误并退出
# @command error_exit $error_str
# @param $error_str     错误内容
# return 1
error_exit(){
    echo "[ERROR] $1"
    exit 1;
}
# 询问选项处理
# @command ask_select $msg
# @param $msg               询问提示文案
# return 1|0
ask_select(){
    if [ "$ARGV_force" = '1' ];then
        return 0
    fi
    local INPUT MSG_TEXT="$1 请输入 [ y/n ]：" REGEXP_TEXT='y|n' ATTEMPT=1
    while [ -z "$INPUT" ]; do
        # 注意：read 不能递归调用，内部read命令将无法获取准备输入，比如放在while处理块内，再开调用read
        read -p "$MSG_TEXT" INPUT
        if printf '%s' "$INPUT"|grep -qP "^($REGEXP_TEXT)$";then
            break
        fi
        INPUT=''
        if ((ATTEMPT >= 10));then
            echo "已经连续输入错误 ${ATTEMPT} 次，终止询问！"
            return 1
        else
            echo "输入错误，请注意输入选项要求！"
            ((ATTEMPT++))
        fi
    done
    if [ $INPUT = 'y' ];then
        return 0
    else
        return 1
    fi
}
# 格式化处理
# @command disk_format $disk
# @param $part_name             格式化写入分区变量名
# @param $disk                  要格式化的硬盘
# return 1|0
disk_format(){
    # 获取当前存在的分区
    local PARTS_PATH=`lsblk -nl $2|awk '$6 == "part" && !$7{print "/dev/"$1}'` END_SECTOR=$SECTOR_NUM
    echo "即将对磁盘 $2 进行分区，扇区大小：$ARGV_sector_size"
    if [ -n "$END_SECTOR" ];then
        if fdisk -l $2|grep -P '^Units'|grep -qP '1\s*\*\s*\d+';then
            # 按扇区数分区
            local START_SECTOR=`fdisk -l /dev/sdb|grep -P '^/dev/'|awk 'END{print $3}'`
            if [ -n "$START_SECTOR" ];then
                END_SECTOR=$[$END_SECTOR + $START_SECTOR + 1]
            fi
            echo "分区大小限制为：$ARGV_part_size ，扇区数：$SECTOR_NUM ，结束扇区数：$END_SECTOR"
        else
            # 按柱面数分区
            END_SECTOR='+'$((PART_SIZE / 1024))'K'
            echo "分区大小限制为：$ARGV_part_size ，分区指定大小：$END_SECTOR"
        fi
    fi
    local PART_INDEX=`echo -e "1\n2\n3\n4\n$(fdisk -l $2|grep -oP "^$2[1-4]\D"|grep -oP '\d+$')"|sort|grep -P '\d+'|uniq -u|head -n 1`
    if [ -z "$PART_INDEX" ];then
        echo "fdisk 分区序号是1~4，当前序号都使用完，无法再分区！"
        return 1
    fi
    fdisk -b $ARGV_sector_size $2 <<EOF
n
p
$PART_INDEX

$END_SECTOR
wq
EOF
    if [ $? = '0' ];then
        # sleep 2
        # 格式化完后再获取唯一多出来的分区
        PARTS_PATH="$PARTS_PATH\n"`lsblk -nl $2|awk '$6 == "part" && !$7{print "/dev/"$1}'`
        PART_PATH=$(printf "$PARTS_PATH"|sort|uniq -u)
        if [ -n "$PART_PATH" ];then
            echo "成功创建主分区：$PART_PATH，并格式化为：$ARGV_type"
            mkfs -t $ARGV_type $PART_PATH
            eval "$1=\$PART_PATH"
            return 0
        fi
    fi
    echo "分区 $2 失败！"
    return 1
}
# 挂载处理
# @command part_mount $part
# @param $part                  要挂载的分区地址
# return 1|0
part_mount(){
    local PART_INFO=(`lsblk -nfl $1|awk '{print $1,$2,$4}'|tail -1`)
    if ((${#PART_INFO[@]} < 1));then
        echo "无法获取分区信息：$1";
    elif [ -z "${PART_INFO[1]}" ];then
        echo "无法获取分区类型：$1";
    elif [ -n "${PART_INFO[2]}" ];then
        echo "分区 $1 已经挂载到：${PART_INFO[2]}";
    else
        local PATH_STR="$ARGV_path" ATTEMPT=1
        while (true); do
            if ((ATTEMPT >= 10));then
                echo "已经连续取消 ${ATTEMPT} 次，终止挂载！"
                return 1
            fi
            if [ -z "$PATH_STR" ];then
                printf '请输入要挂载的目录：'
                read PATH_STR
            fi
            if [ ! -d "$PATH_STR" ];then
                mkdir -p $PATH_STR
            elif [ -n "$(ls -al $PATH_STR|awk '$9!="." && $9!= ".." && $9{print $9}')" ] && ! ask_select "目录 $PATH_STR 不是空的，挂载后会目录内的文件不可访问，确认要挂载？";then
                PATH_STR=''
                ((ATTEMPT++))
                continue
            fi
            break
        done
        if mount $1 $PATH_STR;then
            if [ "$ARGV_temp" != '1' ];then
                if grep -qP "^$1 " /etc/fstab;then
                    echo "/etc/fstab 文件中已经存在 $1 挂载配置，即将替换更新"
                    sed -i -r "s,^$1 .*$,$1 $PATH_STR ${PART_INFO[1]} defaults 0 0," /etc/fstab
                    echo "挂载 $1 => $PATH_STR 成功，并已经更新到 /etc/fstab"
                else
                    echo "$1 $PATH_STR ${PART_INFO[1]} defaults 0 0" >> /etc/fstab
                    echo "挂载 $1 => $PATH_STR 成功，并已经写入 /etc/fstab"
                fi
                if ! mount -a;then
                    echo '请检查 /etc/fstab 文件，是否有配置错误，如果有请手动修改更新，否则重启系统可能会异常！'
                fi
            else
                echo "挂载 $1 => $PATH_STR 成功"
            fi
            echo "删除当前挂载时可调用命令：umount $PATH_STR"
            return 0
        else
            echo "挂载 $1 => $PATH_STR 失败！"
        fi
    fi
    return 1
}
# 容量整理
# @command size_format $var_name $size
# @param $var_name              格式化写入变量名
# @param $size                  容量值，以B为单位
# return 1|0
size_format(){
    local _SIZE
    if(($2 >= 1099511627776));then
        _SIZE=$[$2 / 1099511627776]'T'
    elif(($2 >= 1073741824));then
        _SIZE=$[$2 / 1073741824]'G'
    elif(($2 >= 1048576));then
        _SIZE=$[$2 / 1048576]'M'
    elif(($2 >= 1024));then
        _SIZE=$[$2 / 1024]'K'
    else
        _SIZE=$2'B'
    fi
    eval "$1=\$_SIZE"
}
# 定义参数
ARGUMENTS=('path')
# 定义有值选项
OPTIONS=('-t,--type' '-d,--disk' '--sector-size' '-p,--part-size')
# 定义无值选项
OPTIONALS=('-f,--force' '-h,--help' '--temp')
# 提取安装参数
CALL_INPUT_ARGVS=()
for ((INDEX=1;INDEX<=$#;INDEX++));do
    CALL_INPUT_ARGVS[${#CALL_INPUT_ARGVS[@]}]=${@:$INDEX:1}
done
# 参数默认值
ARGV_type='ext4'
ARGV_sector_size=512
ARGV_part_size=0
# 解析参数
parse_command_param
if [ -n "$ARGV_help" ];then
    echo -e "Description:
    硬盘分区和挂载处理脚本

Usage:
    bash $0.sh [Arguments] [Options ...]

Arguments:
    path                    挂载目录，不指定则在挂载时需要手动输入挂载目录
                            指定挂载目录为单一模式，即目录挂载完成就结束
                            不指定为循环模式，即会循环掉所有未挂载或使用的磁盘引导去挂载

Options:
    -h, --help              显示脚本帮助信息
    -t, --type [=$ARGV_type]      指定格式化类型
    -d, --disk [='']        指定硬盘或分区地址
    --sector-size [=$ARGV_sector_size]    创建分区扇区大小，可选值：512、1024、2048、4096
                            没有特殊要求不需要修改
    -p, --part-size [=$ARGV_part_size]    创建分区大小，此参数将限制创建分区的大小
                            需要指定单位，默认为B，可选单位：B、K、M、G、T
                            分区大小 = 扇区大小 * 扇区数。即分区大小必需是扇区大小的倍数
                            如果大小不够则自动跳过，为0则将硬盘剩余空间全部创建为一个分区
    -f, --force             强制执行不需要询问操作
    --temp                  临时挂载，指定后将不写 /etc/fstab 配置文件

Help:
    循环挂载
        bash $0.sh

    指定挂载
        bash $0.sh /path

    此脚本只用来快速分区和挂载之用，挂载后默认自动写入 /etc/fstab 配置文件中，以便重启均能生效。
    脚本会自动搜索未挂载的分区或未使用的硬盘，引导去分区和挂载操作。已经挂载的分区将不在此脚本处理范围内。
    此操作会影响硬盘分区，需使用root类最高权限账号操作，操作前请确认操作的必要性。

    注意：脚本强制每个磁盘会留下1M空间给EFI启动代码，所以当磁盘还有1M空间未使用时会自动过滤掉。
";
    exit 0
fi
# 参数验证
SECTOR_NUM=''
PART_SIZE=''
if [ -z "$ARGV_sector_size" ] || ! [[ "$ARGV_sector_size" =~ ^(512|1024|2048|4096)$ ]];then
    error_exit "--sector-size 扇区大小值错误，请核对：$ARGV_sector_size"
fi
if [ "$ARGV_part_size" != '0' ];then
    if [ -z "$ARGV_part_size" ] || ! [[ "$ARGV_part_size" =~ ^[1-9][0-9]*[BKMGT]?$ ]];then
        error_exit "--part-size 分区大小值错误，请核对：$ARGV_part_size"
    else
        case $ARGV_part_size in
            *T)
                SIZE_UNIT=1099511627776
                ;;
            *G)
                SIZE_UNIT=1073741824
                ;;
            *M)
                SIZE_UNIT=1048576
                ;;
            *K)
                SIZE_UNIT=1024
                ;;
            *B)
                SIZE_UNIT=1
                ;;
            *)
                ARGV_part_size=$ARGV_part_size'B'
                SIZE_UNIT=1
                ;;
        esac
        PART_SIZE=$[ $SIZE_UNIT * ${ARGV_part_size/[BKMGT]/} ]
        if (( $ARGV_sector_size > $PART_SIZE ));then
            error_exit "--part-size 分区大小不能小于扇区大小，请核对：$ARGV_part_size"
        else
            SECTOR_NUM=$(($PART_SIZE/$ARGV_sector_size + 1))
        fi
    fi
fi
if [ -n "$ARGV_disk" -a -e "$ARGV_disk" ] && ! lsblk -n "$ARGV_disk" 2>&1 >/dev/null;then
    error_exit "--disk 硬盘或分区不存在，请核对：$ARGV_disk"
fi
if [ -z "$ARGV_type" ] || ! which "mkfs.$ARGV_type" >/dev/null;then
    error_exit "--type 分区错误，请核对：$ARGV_type"
fi
# 搜索未挂载的分区
DISKS_ARRAY=()
while read ITEM;do
    BLOCK_ARRAY=($ITEM)
    BLOCK_SIZE=(`lsblk -bna ${BLOCK_ARRAY[0]}|awk 'BEGIN{use=0;part=0}$6 != "disk" && $7 != ""{use += $4} $6 == "part"{part += $4}END{print use,part}'`)
    if (( ${BLOCK_ARRAY[3]} <= ${BLOCK_SIZE[0]} )) || ([ "${BLOCK_ARRAY[5]}" = 'part' ] && (( ${BLOCK_SIZE[0]} > 0 )));then
        continue
    elif [ "${BLOCK_ARRAY[5]}" = 'disk' ];then
        BLOCK_ARRAY[3]=$[ ${BLOCK_ARRAY[3]} - ${BLOCK_SIZE[1]} ]
        if (( ${BLOCK_ARRAY[3]}/1048576 <= 1 ));then
            continue
        fi
    fi
    DISKS_ARRAY[${#DISKS_ARRAY[@]}]="${BLOCK_ARRAY[@]}"
done <<EOF
`lsblk -bnal $ARGV_disk|awk '$6 ~ "disk|part" && !$7 {$1=("/dev/"$1);print}'`
EOF

if ((${#DISKS_ARRAY[@]} < 1));then
    error_exit "没有搜索到未挂载或未使用完的磁盘信息！"
fi
for ((INDEX=0;INDEX<${#DISKS_ARRAY[@]};INDEX++));do
    ARRAY_DATA=(${DISKS_ARRAY[$INDEX]})
    size_format UNUSERD_SIZE ${ARRAY_DATA[3]}
    if [ -n "$PART_SIZE" ] && (($PART_SIZE > ${ARRAY_DATA[3]}));then
        if [ ${ARRAY_DATA[5]} = 'disk' ];then
            echo "硬盘 ${ARRAY_DATA[0]} 未用空间：$UNUSERD_SIZE 不够：$ARGV_part_size ，跳过挂载处理"
        else
            echo "分区 ${ARRAY_DATA[0]} 可用空间：$UNUSERD_SIZE 不够：$ARGV_part_size ，跳过挂载处理"
        fi
        continue
    fi
    if [ ${ARRAY_DATA[5]} = 'disk' ];then
        if ask_select "硬盘 ${ARRAY_DATA[0]} 未用空间：$UNUSERD_SIZE 是否格式化再挂载？" && disk_format PART_NAME ${ARRAY_DATA[0]};then
            PART_INFO=(`lsblk -nl $PART_NAME|awk '$6 == "part" && $7 == "" {print "/dev/"$1,$4}'|tail -1`)
            echo "硬盘 ${ARRAY_DATA[0]} 刚创建分区 ${PART_INFO[0]} 可用空间：${PART_INFO[1]} 即将挂载"
            if part_mount ${PART_INFO[0]} && [ -n "$ARGV_path" ];then
                exit 0
            fi
        fi
    else
        if [ -z "${ARRAY_DATA[6]}" ] && ask_select "分区 ${ARRAY_DATA[0]} 未挂载，可用空间：$UNUSERD_SIZE 是否挂载？" && part_mount ${ARRAY_DATA[0]} && [ -n "$ARGV_path" ];then
            exit 0
        fi
    fi
done
