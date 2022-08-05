#!/bin/bash
############################################################################
# 工具脚本公共处理文件，用来转义$@数据使用其参数能作为字符串进行调用
# 通过此脚本处理的参数可直接用来给run_msg运行，而不会受部分歧义字符干扰
# 此脚本不可单独运行，需要在其它脚本中引用执行
############################################################################

if [ "$(basename "$0")" = "$(basename "${BASH_SOURCE[0]}")" ];then
    error_exit "${BASH_SOURCE[0]} 脚本是共用文件必需使用source调用"
fi
# 定义内部参数
ARGVS_ARRAY=()
for ((_INDEX_=1;_INDEX_<=$#;_INDEX_++));do
    eval _ARV_ITEM_=\${$_INDEX_}
    if [ -n "$_ARV_ITEM_" ];then
        _ARV_ITEM_=${_ARV_ITEM_//\\/\\\\}
        _ARV_ITEM_=${_ARV_ITEM_//\"/\\\"}
        ARGVS_ARRAY[${#ARGVS_ARRAY[@]}]=\"$_ARV_ITEM_\"
    fi
done
unset _INDEX_ _ARV_ITEM_
