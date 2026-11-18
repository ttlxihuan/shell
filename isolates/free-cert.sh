#!/bin/bash
# 免费https证书申请脚本，自动更新证书，并刷新服务器配置
# 需要安装 socat 命令

# 在这里填写DNS平台配置参数
# 阿里云DNS解析配置
# export Ali_Key="your_ali_id"
# export Ali_Secret="your_ali_key"

# 腾讯云DNS解析配置
# export Tencent_SecretId="your_tencent_id"
# export Tencent_SecretKey="your_tencent_key"

# Cloudflare DNS解析配置
# export CF_Token="your_cf_id"
# export CF_Account_ID="your_cf_account_id"
# export CF_Zone_ID="your_cf_zone_id"

# AWS Route53 DNS解析配置
# export AWS_ACCESS_KEY_ID="your_aws_id"
# export AWS_SECRET_ACCESS_KEY="your_aws_secret_key"

# 输出帮助信息
show_help(){
    echo "
基于acme.sh免费https证书申请脚本，自动更新证书，并刷新服务器配置。

命令：
    $(basename "${BASH_SOURCE[0]}") dns server [-h|-?]

参数：
    dns                 指定DNS解析平台，注意需要在外部配置相关环境配置变量，具体请参考acme.sh官方文档。
                        常用DNS解析平台：
                            dns_ali     阿里云DNS解析
                            dns_tencent 腾讯云DNS解析
                            dns_cf      CloudflareDNS解析
                            dns_aws     AWS Route53 DNS解析
    domains             要申请的域名配置文件，每行一个域名
    
选项：
    --before-days       默认10天，指定证书自动更新时间间隔
    --home-dir          工作目录，默认当前目录
    --save-dir          保存证书目录，默认当前目录
    --reload-cmd        刷新服务器配置命令，让证书生效
    --save-format-cert  保存证书格式，默认： {DOMAIN}.pem
    --save-format-key   保存证书密钥格式，默认： {DOMAIN}.key
    -h, -?              显示帮助信息

说明：
    证书申请需要dns解析平台用户域名验证，acme.sh支持上百个平台的dns解析，包含国内外主流的dns解析平台。
    支持的DNS官方文档：https://github.com/acmesh-official/acme.sh/wiki/dnsapi
    示例：
    bash ./free-cert.sh dns_ali ./gitlab.conf --home-dir ./ --save-dir /usr/local/nginx/conf/certs/ --reload-cmd \"/usr/local/nginx/sbin/nginx -t && /usr/local/nginx/sbin/nginx -s reload\"
"
    exit 0
}
# 输出错误信息并终止运行
show_error(){
    echo "[error] $1" >&2
    exit 1
}
if_error(){
    if [ $? != 0 ];then
        show_error "$1"
    fi
}

# 参数处理
if [ $# = 0 ];then
    show_help
fi

BEFORE_DAYS=10
HOME_DIR=$(pwd)
SAVE_FORMAT_CERT="{DOMAIN}.pem"
SAVE_FORMAT_KEY="{DOMAIN}.key"

for((INDEX=1; INDEX<=$#; INDEX++));do
    case "${@:$INDEX:1}" in
        --before-days)
            BEFORE_DAYS=${@:((++INDEX)):1}
        ;;
        --home-dir)
            HOME_DIR=${@:((++INDEX)):1}
        ;;
        --save-dir)
            SAVE_DIR=${@:((++INDEX)):1}
        ;;
        --reload-cmd)
            RELOAD_CMD=${@:((++INDEX)):1}
        ;;
        --save-format-cert)
            SAVE_FORMAT_CERT=${@:((++INDEX)):1}
        ;;
        --save-format-key)
            SAVE_FORMAT_KEY=${@:((++INDEX)):1}
        ;;
        -h|-\?)
            show_help
        ;;
        *)
            if [ -z "$DNS_PLATFORM" ];then
                DNS_PLATFORM=${@:$INDEX:1}
            elif [ -z "$DOMAINS_FILE" ];then
                DOMAINS_FILE=${@:$INDEX:1}
            else
                show_error "未知参数选项：${@:$INDEX:1}"
            fi
        ;;
    esac
done

if [ -z "$DNS_PLATFORM" ];then
    show_error "请指定DNS解析平台"
fi
if [ -z "$DOMAINS_FILE" -o ! -e "$DOMAINS_FILE" ];then
    show_error "请指定要申请的域名配置文件"
fi

if [ ! -d "$HOME_DIR" ] && ! mkdir -p "$HOME_DIR";then
    error_exit "工作目录创建失败：$HOME_DIR"
fi

HOME_DIR=$(cd "$HOME_DIR" 2>/dev/null && pwd)

if [ -n "$SAVE_DIR" -a ! -d "$SAVE_DIR" ] && ! mkdir -p "$SAVE_DIR";then
    error_exit "保存证书目录创建失败：$SAVE_DIR"
fi

if [ ! -e ./acme.sh ];then
    # 下载acme.sh
    if wget https://github.com/acmesh-official/acme.sh/archive/master.tar.gz; then
        tar -vzxf master.tar.gz && mv -f ./acme.sh-master/* ./ && rm -rf ./acme.sh-master
    elif ! wget -O acme.sh https://fastly.jsdelivr.net/gh/acmesh-official/acme.sh@master/acme.sh && ! wget -O acme.sh https://raw.githubusercontent.com/acmesh-official/acme.sh/refs/heads/master/acme.sh; then
        error_exit "acme.sh 下载失败"
    fi

    if [ ! -e ./acme.sh ];then
        error_exit "acme.sh 下载失败"
    fi

    chmod +x ./acme.sh

    if ! ./acme.sh -v; then
        error_exit "acme.sh 安装失败"
    fi

    # 修改默认CA为letsencrypt的目录
    ./acme.sh --set-default-ca --server letsencrypt --home "$HOME_DIR"
fi

if [ ! -e "$HOME_DIR/dnsapi/${DNS_PLATFORM}.sh" ] && ! ./acme.sh --home "$HOME_DIR" --upgrade;then
    # 获取DNS解析平台脚本
    error_exit "没有找到钩子${DNS_PLATFORM}.sh脚本"
fi

# 检查证书是否过期
check_cert() {
    # 检查证书是否存在
    if [ ! -e "$1" ];then
        return 1
    fi
    # 获取证书到期时间
    CERT_EXPIRE_DATE=$(openssl x509 -in "$1" -noout -enddate | cut -d= -f2 | xargs -I{} date -d "{}" +%s)
    NOW_DATE=$(date +%s)
    (((CERT_EXPIRE_DATE - NOW_DATE) > 86400 * BEFORE_DAYS))
}

apply_cert() {
    if ./acme.sh --issue -d "$1" --dns "$DNS_PLATFORM" --home "$HOME_DIR" --cert-home "$HOME_DIR/certs" --force;then
        echo "申请成功：$1"
    else
        echo "申请失败：$1"
        return 1
    fi
}

reload_cert() {
    if [ -n "$SAVE_DIR" ];then
        # 判断当前使用的证书是否已经过期了
        SAVE_CERT_FILE="${SAVE_FORMAT_CERT//\{DOMAIN\}/$DOMAIN}"
        SAVE_KEY_FILE="${SAVE_FORMAT_KEY//\{DOMAIN\}/$DOMAIN}"
        if [ -e "$SAVE_DIR/${SAVE_CERT_FILE}" ] && check_cert "$SAVE_DIR/${SAVE_CERT_FILE}";then
            return
        fi
        cp -f "$HOME_DIR/certs/${1}_ecc/fullchain.cer" "$SAVE_DIR/${SAVE_CERT_FILE}"
        cp -f "$HOME_DIR/certs/${1}_ecc/${1}.key" "$SAVE_DIR/${SAVE_KEY_FILE}"
    elif [ "$2" == "has" ];then
        return
    fi
    if [ -n "$RELOAD_CMD" ];then
        eval $RELOAD_CMD
    fi
}

for DOMAIN in $(cat "$DOMAINS_FILE"); do
    if check_cert "$HOME_DIR/certs/${DOMAIN}_ecc/fullchain.cer";then
        reload_cert "$DOMAIN" has
    elif apply_cert "$DOMAIN";then
        reload_cert "$DOMAIN" apply
    fi
done
