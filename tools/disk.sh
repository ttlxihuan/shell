#!/bin/bash
# 自动分区和挂载工具
# 1、自动分区
# 2、自动格式化
# 3、自动挂载并写入/etc/fstab配置文件中
#
# 了解语法：
# bash disk.sh -h

# 参数信息配置
SHELL_RUN_DESCRIPTION='硬盘分区和挂载处理脚本'
SHELL_RUN_HELP='
循环挂载
    bash $0.sh

指定挂载目录
    bash $0.sh /path

此脚本只用来快速分区和挂载之用，挂载后默认自动写入 /etc/fstab 配置文件中，以便重启均能生效。
脚本会自动搜索未挂载的分区或未使用的硬盘，引导去分区和挂载操作。已经挂载的分区将不在此脚本处理范围内。
此操作会影响硬盘分区，需使用root类最高权限账号操作，操作前请确认操作的必要性。

注意：脚本强制每个磁盘会留下1M空间给EFI启动代码，所以当磁盘还有1M空间未使用时会自动过滤掉。
'
DEFINE_TOOL_PARAMS='
[path]挂载目录，不指定则在挂载时需要手动输入挂载目录
#指定挂载目录为单一模式，即目录挂载完成就结束
#不指定为循环模式，即会循环掉所有未挂载或使用的磁盘引导去挂载
[-t, --type=ext4]指定格式化类型
[-d, --disk=""]指定硬盘或分区地址
[--sector-size=512]创建分区扇区大小，可选值：512、1024、2048、4096
#没有特殊要求不需要修改
[-p, --part-size=0]创建分区大小，此参数将限制创建分区的大小
#需要指定单位，默认为B，可选单位：B、K、M、G、T
#分区大小 = 扇区大小 * 扇区数。即分区大小必需是扇区大小的倍数
#如果大小不够则自动跳过，为0则将硬盘剩余空间全部创建为一个分区
[-f, --force]强制执行不需要询问操作
[--temp]临时挂载，指定后将不写 /etc/fstab 配置文件
'
source $(cd $(dirname ${BASH_SOURCE[0]}); pwd)/../includes/tool.sh || exit
# 格式化处理
# @command disk_format $disk
# @param $part_name             格式化写入分区变量名
# @param $disk                  要格式化的硬盘
# return 1|0
disk_format(){
    # 获取当前存在的分区
    local PARTS_PATH=`lsblk -nl $2|awk '$6 == "part" && !$7{print "/dev/"$1}'` END_SECTOR=$SECTOR_NUM
    info_msg "即将对磁盘 $2 进行分区，扇区大小：$ARGV_sector_size"
    if [ -n "$END_SECTOR" ];then
        if fdisk -l $2|grep -P '^Units'|grep -qP '1\s*\*\s*\d+';then
            # 按扇区数分区
            local START_SECTOR=`fdisk -l /dev/sdb|grep -P '^/dev/'|awk 'END{print $3}'`
            if [ -n "$START_SECTOR" ];then
                END_SECTOR=$[$END_SECTOR + $START_SECTOR + 1]
            fi
            info_msg "分区大小限制为：$ARGV_part_size ，扇区数：$SECTOR_NUM ，结束扇区数：$END_SECTOR"
        else
            # 按柱面数分区
            END_SECTOR='+'$((PART_SIZE / 1024))'K'
            info_msg "分区大小限制为：$ARGV_part_size ，分区指定大小：$END_SECTOR"
        fi
    fi
    local PART_INDEX=`echo -e "1\n2\n3\n4\n$(fdisk -l $2|grep -oP "^$2[1-4]\D"|grep -oP '\d+$')"|sort|grep -P '\d+'|uniq -u|head -n 1`
    if [ -z "$PART_INDEX" ];then
        warn_msg "fdisk 分区序号是1~4，当前序号都使用完，无法再分区！"
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
            info_msg "成功创建主分区：$PART_PATH，并格式化为：$ARGV_type"
            mkfs -t $ARGV_type $PART_PATH
            eval "$1=\$PART_PATH"
            return 0
        fi
    fi
    warn_msg "分区 $2 失败！"
    return 1
}
# 挂载处理
# @command part_mount $part
# @param $part                  要挂载的分区地址
# return 1|0
part_mount(){
    local PART_INFO=(`lsblk -nfl $1|awk '{print $1,$2,$4}'|tail -1`)
    if ((${#PART_INFO[@]} < 1));then
        warn_msg "无法获取分区信息：$1";
    elif [ -z "${PART_INFO[1]}" ];then
        warn_msg "无法获取分区类型：$1";
    elif [ -n "${PART_INFO[2]}" ];then
        warn_msg "分区 $1 已经挂载到：${PART_INFO[2]}";
    else
        local PATH_STR="$ARGU_path" ATTEMPT=1
        while (true); do
            if ((ATTEMPT >= 10));then
                warn_msg "已经连续取消 ${ATTEMPT} 次，终止挂载！"
                return 1
            fi
            if [ -z "$PATH_STR" ];then
                printf '请输入要挂载的目录：'
                read PATH_STR
            fi
            if [ ! -d "$PATH_STR" ];then
                mkdir -p $PATH_STR
            elif [ -n "$(ls -al $PATH_STR|awk '$9!="." && $9!= ".." && $9{print $9}')" ] && ! ask_permit "目录 $PATH_STR 不是空的，挂载后会目录内的文件不可访问，确认要挂载？";then
                PATH_STR=''
                ((ATTEMPT++))
                continue
            fi
            break
        done
        if mount $1 $PATH_STR;then
            if [ "$ARGV_temp" != '1' ];then
                if grep -qP "^$1 " /etc/fstab;then
                    info_msg "/etc/fstab 文件中已经存在 $1 挂载配置，即将替换更新"
                    sed -i -r "s,^$1 .*$,$1 $PATH_STR ${PART_INFO[1]} defaults 0 0," /etc/fstab
                    info_msg "挂载 $1 => $PATH_STR 成功，并已经更新到 /etc/fstab"
                else
                    echo "$1 $PATH_STR ${PART_INFO[1]} defaults 0 0" >> /etc/fstab
                    info_msg "挂载 $1 => $PATH_STR 成功，并已经写入 /etc/fstab"
                fi
                if ! mount -a;then
                    info_msg '请检查 /etc/fstab 文件，是否有配置错误，如果有请手动修改更新，否则重启系统可能会异常！'
                fi
            else
                info_msg "挂载 $1 => $PATH_STR 成功"
            fi
            info_msg "删除当前挂载时可调用命令：umount $PATH_STR"
            return 0
        else
            warn_msg "挂载 $1 => $PATH_STR 失败！"
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
    BLOCK_SIZE=(`lsblk -bna ${BLOCK_ARRAY[0]}|awk 'BEGIN{use=0;part=0}$6 != "disk" && $7 != ""{use += $4} $6 == "part"{part += $4}END{printf("%.0f %.0f",use,part)}'`)
    if (( ${BLOCK_ARRAY[3]} <= ${BLOCK_SIZE[0]} )) || ([ "${BLOCK_ARRAY[5]}" = 'part' ] && (( ${BLOCK_SIZE[0]} > 0 )));then
        continue
    elif [ "${BLOCK_ARRAY[5]}" = 'disk' ];then
        BLOCK_ARRAY[3]=$[ ${BLOCK_ARRAY[3]} - ${BLOCK_SIZE[1]} ]
        if (( ${BLOCK_ARRAY[3]}/1048576 <= 2 ));then
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
            info_msg "硬盘 ${ARRAY_DATA[0]} 未用空间：$UNUSERD_SIZE 不够：$ARGV_part_size ，跳过挂载处理"
        else
            info_msg "分区 ${ARRAY_DATA[0]} 可用空间：$UNUSERD_SIZE 不够：$ARGV_part_size ，跳过挂载处理"
        fi
        continue
    fi
    if [ ${ARRAY_DATA[5]} = 'disk' ];then
        if ask_permit "硬盘 ${ARRAY_DATA[0]} 未用空间：$UNUSERD_SIZE 是否格式化再挂载？" && disk_format PART_NAME ${ARRAY_DATA[0]};then
            PART_INFO=(`lsblk -nl $PART_NAME|awk '$6 == "part" && $7 == "" {print "/dev/"$1,$4}'|tail -1`)
            info_msg "硬盘 ${ARRAY_DATA[0]} 刚创建分区 ${PART_INFO[0]} 可用空间：${PART_INFO[1]} 即将挂载"
            if part_mount ${PART_INFO[0]} && [ -n "$ARGU_path" ];then
                exit 0
            fi
        fi
    else
        if [ -z "${ARRAY_DATA[6]}" ] && ask_permit "分区 ${ARRAY_DATA[0]} 未挂载，可用空间：$UNUSERD_SIZE 是否挂载？" && part_mount ${ARRAY_DATA[0]} && [ -n "$ARGU_path" ];then
            exit 0
        fi
    fi
done
