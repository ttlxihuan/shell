#!/bin/bash
# 自动分区和挂载工具
# 1、自动分区
# 2、自动格式化
# 3、自动挂载并写入/etc/fstab配置文件中
#
# 了解语法：
# bash disk.sh -h
#
# 注意：
#  1、系统分区有分区模式和文件系统组成。
#   分区模式是记录分区起始及相关引导数据（用来统一划分空间规则），通过固定写入位置方便识别和读取（主要是硬盘开始位置，结束位置也可能），模式有：MBR（Master Boot Record 主引导记录）和GPT（Globally Unique Identifier Partition Table 全局唯一标识分区表）
#       MBR 在1983年在IBM PC DOS 2.0中提出，最大支持2.2T硬盘（地址空间长度限制），最多4个主分区，再增加只能使用扩展分区，在linux系统下仅4个分区（主分区+扩展分区）
#       GPT 是MBR的延申（部分系统会提示在实验阶段），兼容MBR模式，最大支持ZB级硬盘（1ZB=1TB*1024*1024*1024），分区个数受系统最多个数限制（系统是否支持GPT需要额外查对，一般高版本系统均支持）
#       分区模式支持容量大受扇区大小波动（扇区大小主要有：512B、1024B、2048B、4096B），分区表中只记录扇区数，所以扇区越小支持容量越小，但空间利用更好（扇区是存储数据最小单位，不足扇区大小也会占用一个扇区空间）
#   文件系统是各系统提供的分区存储数据结构，不同的文件系统针对不同的应用场景，合理选用文件系统能提升性能或效率，文件系统也有容量限制使用前需要了解下。
#   文件系统是通过簇或块来读写磁盘（也可以叫扇区簇，它是一段连续扇区的地址，即多个扇区为一个簇），簇可以提升磁盘访问效率。
#       linux系统文件系统主要有：
#           ext2    Ext是 GNU/Linux 系统中标准的文件系统，其特点为存取文件的性能极好，对于中小型的文件更显示出优势，这主要得利于其簇快取层的优良设计。
#                   簇最大为4KB，单文件最大 2048GB，分区容量上限为 16384GB。最多32000 个子目录。 inode大小128 字节
#           ext3    Ext3是一种日志式文件系统，是对ext2系统的扩展，它兼容ext2。
#                   此类文件系统最大的特色是，它会将整个磁盘的写入动作完整记录在磁盘的某个区域上，以便有需要时可以回溯追踪。
#                   由于详细纪录了每个细节，故当在某个过程中被中断时，系统可以根据这些记录直接回溯并重整被中断的部分，而不必花时间去检查其他的部分，故重整的工作速度相当快，几乎不需要花时间。
#                   仅增加日志记录功能，空间相关并未调整
#           ext4    Linux kernel 自 2.6.28 开始正式支持新的文件系统 Ext4。Ext4 是 Ext3 的改进版，修改了 Ext3 中部分重要的数据结构，而不仅仅像 Ext3 对 Ext2 那样，只是增加了一个日志功能而已。
#                   单文件最大 16TB，分区容量上限为 1EB（=1TB*1024*1024）。无子目录限制。允许关闭日志动作记录节点节省开销。在线碎片整理。默认inode大小256字节。
#           btrfs   目标是取代Linux目前的ext3文件系统，改善ext3的空间限制，特别是单个文件的大小
#           xfs     它至今仍作为 SGI 基于 IRIX 的产品（从工作站到超级计算机）的底层文件系统来使用，这种文件系统所具有的可伸缩性能够满足最苛刻的存储需求
#
# 2、虚拟机新增磁盘时需要注意磁盘是否增加完成。创建磁盘时可能不会自动加载到虚拟机上，可能还需要增加存在磁盘进行加载处理，否则无法扫描出新增加磁盘。
# 3、挂载分区无效（无报错），通过 tail -n 30 /var/log/messages 命令查看有：systemd: Unit x.mount is bound to inactive unit dev-x.device. Stopping, too. 之类提示时
#    首先去掉 /etc/fstab 有相关目录或分区的配置，再执行 systemctl daemon-reload 命令，重新挂载即可。

# 参数信息配置
SHELL_RUN_DESCRIPTION='硬盘分区和挂载处理脚本'
SHELL_RUN_HELP="
循环挂载
    bash $0

指定挂载目录
    bash $0 /path

此脚本只用来快速分区和挂载之用，挂载后默认自动写入 /etc/fstab 配置文件中，以便重启均能生效。
脚本会自动搜索未挂载的分区或未使用的硬盘，引导去分区和挂载操作。已经挂载的分区将不在此脚本处理范围内。
此操作会影响硬盘分区，需使用root类最高权限账号操作，操作前请确认操作的必要性。

注意：脚本强制每个磁盘会留下1M空间给EFI启动代码，所以当磁盘还有1M空间未使用时会自动过滤掉。
"
# 获取系统支持的分区格式
MKFS_BIN_PATH=$(which mkfs)
if [ $? = '0' ];then
    MKFS_TYPES=$(echo $(find $(dirname $MKFS_BIN_PATH) -name mkfs.*|grep -oP '\w+$')|sort|sed -r 's/\s+/,/g')
else
    MKFS_TYPES='ext2,ext3,ext4'
fi
DEFINE_TOOL_PARAMS='
[path]挂载目录，不指定则在挂载时需要手动输入挂载目录
#指定挂载目录为单一模式，即目录挂载完成就结束
#不指定为循环模式，即会循环掉所有未挂载或使用的磁盘引导去挂载
[-t, --type=ext4, {required|in:'$MKFS_TYPES'}]指定格式化类型，以当前系统支持类型为准
[-d, --disk=, {file}]指定硬盘或分区地址
[--sector-size=512, {required|int|in:512,1024,2048,4096}]创建分区扇区大小，可选值：512、1024、2048、4096
#没有特殊要求不需要修改
[-p, --part-size=0, {required|regexp:"^(0|[1-9][0-9]*)(\.[0-9]+)?[BKMGT]?$"}]创建分区大小，此参数将限制创建分区的大小
#需要指定单位，默认为B，可选单位：B、K、M、G、T
#分区大小 = 扇区大小 * 扇区数。即分区大小必需是扇区大小的倍数
#如果大小不够则自动跳过，为0则将硬盘剩余空间全部创建为一个分区
[-s, --scsi-scan]重新扫描系统磁盘，识别新增磁盘
[-f, --force]强制执行不需要询问操作
[-g, --use-gpt]强制使用GPT分区模式
#非强制GPT分区模式会在磁盘空间超过2TB时自动选择GPT模式
#GPT分区模式支持更大磁盘容量
[--temp]临时挂载，指定后将不写 /etc/fstab 配置文件
'
source "$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"/../includes/tool.sh || exit
# 格式化处理
# @command disk_format $disk
# @param $part_name             格式化写入分区变量名
# @param $disk                  要格式化的硬盘
# return 1|0
disk_format(){
    # 获取当前存在的分区
    local START_SECTOR END_SECTOR='' PARTS_PATH=$(lsblk -nl $2|awk '$6 == "part" && !$7{print "/dev/"$1}') DISL_SIZE=$(lsblk -nlb $2|awk '$6 == "disk"{print $4}')
    if [ "$USE_GPT" = 1 ];then
        local PART_INDEX=$(parted $2 -s print 2>&1|awk '{if(NR > 4){print $1}}'|grep -P '\d+'|tail -n 1)
        START_SECTOR=1
        if ((PART_INDEX > 1));then
            # 如果不是第一个分区则需要定位开始位置
            START_SECTOR=$(parted $2 -s print|awk '{if(NR>4){print $3}}'|grep -P '\d+'|tail -n 1)
        fi
        if [ -n "$SECTOR_NUM" ];then
            # 如果不是第一个分区则需要定位结束位置
            if ((PART_INDEX > 1));then
                local START_SECTOR_BIT
                size_switch START_SECTOR_BIT $START_SECTOR
                END_SECTOR=$((PART_SIZE + START_SECTOR_BIT))
            else
                END_SECTOR=$PART_SIZE
            fi
            # 超出总大小则改为100%
            if ((END_SECTOR >= DISL_SIZE));then
                END_SECTOR='100%'
            else
                END_SECTOR=${END_SECTOR}B
            fi
        else
            END_SECTOR='100%'
        fi
        info_msg "即将对磁盘 $2 进行分区，分区号 $PART_INDEX ，，分区工具 parted"
        # 判断分区模式
        if ! parted $2 -s print|grep -qP '^Partition Table: gpt';then
            parted $2 <<EOF
mklabel gpt
yes
quit
EOF
        fi
        # 分区类型，分区个数限制基本没有（个数很多），主分区最少一个
        local PART_TYPE='primary'
        if (( PART_INDEX > 1 ));then
            PART_TYPE='extended'
        fi
        parted $2 <<EOF
mkpart $PART_TYPE $ARGV_type ${START_SECTOR:-1} $END_SECTOR
align-check optimal $PART_INDEX
quit
EOF
    else
        local PART_INDEX=`echo -e "1\n2\n3\n4\n$(fdisk -l $2 2>&1|grep -oP "^$2[1-4]+"|grep -oP '\d+$')"|sort|grep -P '\d+'|uniq -u|head -n 1`
        if [ -n "$SECTOR_NUM" ];then
            if fdisk -l $2 2>&1|grep -P '^Units'|grep -qP '1\s*\*\s*\d+';then
                # 按扇区数分区
                START_SECTOR=`fdisk -l /dev/sdb 2>&1|grep -P '^/dev/'|awk 'END{print $3}'`
                if [ -n "$START_SECTOR" ];then
                    END_SECTOR=$(($SECTOR_NUM + $START_SECTOR + 1))
                fi
                info_msg "分区大小限制为：$ARGV_part_size ，扇区数：$SECTOR_NUM ，结束扇区数：$END_SECTOR"
            else
                # 按柱面数分区
                END_SECTOR='+'$((PART_SIZE / 1024))'K'
                info_msg "分区大小限制为：$ARGV_part_size ，分区指定大小：$END_SECTOR"
            fi
            # 超出总大小则改为空
            local END_SECTOR_BIT
            size_switch END_SECTOR_BIT $END_SECTOR
            if ((END_SECTOR_BIT >= DISL_SIZE));then
                END_SECTOR=''
            fi
        fi
        if [ -z "$PART_INDEX" ];then
            warn_msg "fdisk 分区序号是1~4，当前序号都使用完，无法再分区！"
            return 1
        fi
        # 分区类型，主分区最多3个，扩展分区最多3个，最多4个分区
        local PART_TYPE='p'
        if (( PART_INDEX > 3 ));then
            PART_TYPE='e'
        fi
        info_msg "即将对磁盘 $2 进行分区，分区号 $PART_INDEX ，扇区大小：$ARGV_sector_size，分区工具 fdisk"
        fdisk -b $ARGV_sector_size $2 2>&1 <<EOF
n
$PART_TYPE
$PART_INDEX

$END_SECTOR
wq
EOF
    fi
    partprobe
    # 格式化完后再获取唯一多出来的分区
    PARTS_PATH="$PARTS_PATH\n"`lsblk -nl $2|awk '$6 == "part" && !$7{print "/dev/"$1}'`
    PART_PATH=$(printf "$PARTS_PATH"|sort|uniq -u)
    if [ -n "$PART_PATH" ];then
        info_msg "成功创建主分区：$PART_PATH"
        part_format $PART_PATH
        eval "$1=\$PART_PATH"
        return 0
    fi
    warn_msg "分区 $2 失败！"
    return 1
}
# 格式化分区
# @command part_format $part
# @param $part                  要格式化的分区地址
# return 1|0
part_format(){
    if [ -n "$1" -a -e "$1" ];then
        local PART_FSTYPE=$(lsblk --output FSTYPE -n $1)
        if [ "$PART_FSTYPE" != "$ARGV_type" ];then
            info_msg "格式化分区 $1 为：$ARGV_type"
            mkfs -t $ARGV_type $1
        fi
    else
        warn_msg "分区 $1 不存在！"
    fi
}
# 挂载处理
# @command part_mount $part
# @param $part                  要挂载的分区地址
# return 1|0
part_mount(){
    part_format "$1"
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
        PATH_STR=$(cd "$PATH_STR";pwd);
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
# 使用GPT分区模式，如果系统不支持则跳过
# @command use_gpt $disk $size
# @param $disk                  要格式化的硬盘
# @param $size                  容量值，以B为单位
# return 1|0
use_gpt(){
    # 验证分区模式是否已经为GPT，如果是则自动使用GPT模式进行分区
    if fdisk -l $1 2>&1|grep -qP '(use|support) GPT\W' || [ "$ARGV_use_gpt" = 1 ];then
        USE_GPT=1
        info_msg "使用GPT分区模式创建分区"
    else
        # 容量超过2TB时需要使用GPT分区模式，且分区工具使用parted
        math_compute USE_GPT "${2} > (1024 ^ 4 * 2)"
        [ "$USE_GPT" = 1 ] && info_msg "空间超过2TB将自动强制使用GPT分区模式创建分区"
    fi
    # 安装必备工具
    [ "$USE_GPT" = 1 ] && tools_install parted
}
# 参数验证
SECTOR_NUM='' PART_SIZE=''
if [ "$ARGV_part_size" != '0' ];then
    size_switch PART_SIZE $ARGV_part_size
    if (( $ARGV_sector_size > $PART_SIZE ));then
        error_exit "--part-size 分区大小不能小于扇区大小"
    else
        SECTOR_NUM=$(($PART_SIZE/$ARGV_sector_size + 1))
    fi
    if ! [[ "$ARGV_part_size" =~ [0-9]+[BKMGT]$ ]];then
        ARGV_part_size="${ARGV_part_size}B"
    fi
fi
if [ -n "$ARGV_disk" ] && ! lsblk -n "$ARGV_disk" 2>&1 >/dev/null;then
    error_exit "--disk 硬盘或分区不存在"
fi
# 重新扫描系统磁盘，识别出增加或未识别的磁盘
if [ "$ARGV_scsi_scan" = 1 ];then
    info_msg "扫码总线磁盘信息"
    for HOST_PATH in $(find /sys/class/scsi_host -path '*/host*'); do
        HOST_PATH="$HOST_PATH/scan"
        if [ -e "$HOST_PATH" ];then
            info_msg "$HOST_PATH"
            echo '- - -' > "$HOST_PATH"
        else
            warn_msg "$HOST_PATH"
        fi
    done
fi
# 搜索未挂载的分区
DISKS_ARRAY=() USE_GPT=0
while read ITEM;do
    BLOCK_ARRAY=($ITEM)
    if [ ${#BLOCK_ARRAY[@]} = '0' ];then
        continue
    fi
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
    info_msg "没有搜索到未挂载或未使用完的磁盘信息！"
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
        FREE_SIZE=${ARRAY_DATA[3]}
        use_gpt ${ARRAY_DATA[0]} ${ARRAY_DATA[3]}
        while ((FREE_SIZE > PART_SIZE)) && ask_permit "硬盘 ${ARRAY_DATA[0]} 未用空间：$UNUSERD_SIZE 是否格式化再挂载？" && disk_format PART_NAME ${ARRAY_DATA[0]};do
            PART_INFO=(`lsblk -nl $PART_NAME|awk '$6 == "part" && $7 == "" {print "/dev/"$1,$4}'|tail -1`)
            info_msg "硬盘 ${ARRAY_DATA[0]} 刚创建分区 ${PART_INFO[0]} 可用空间：${PART_INFO[1]} 即将挂载"
            if part_mount ${PART_INFO[0]} && [ -n "$ARGU_path" ];then
                exit 0
            fi
            FREE_SIZE=$((PART_SIZE > 0 ? FREE_SIZE - PART_SIZE : 0))
            size_format UNUSERD_SIZE $FREE_SIZE
        done
    else
        if [ -z "${ARRAY_DATA[6]}" ] && ask_permit "分区 ${ARRAY_DATA[0]} 未挂载，可用空间：$UNUSERD_SIZE 是否挂载？" && part_mount ${ARRAY_DATA[0]} && [ -n "$ARGU_path" ];then
            exit 0
        fi
    fi
done
