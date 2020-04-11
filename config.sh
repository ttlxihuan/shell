#!/bin/bash

#基本安装目录
INSTALL_BASE_PATH="/usr/local"

# ************** 包管理器安装命令 ************** #
# 此配置设置支持的系统包管理器，用于不同的系统来运行
# 安装命令
PACKGE_MANAGER_INSTALL_COMMAND=('yum -y install' 'apt -y install' 'dnf -y install' 'pkg -y install')
# 删除命令
PACKGE_MANAGER_REMOVE_COMMAND=('yum -y erase' 'apt -y remove' 'dnf -y erase' 'pkg -y delete')
# 已经安装命令
# PACKGE_MANAGER_CHECK_COMMAND=('yum list' 'apt list' 'dnf list' 'pkg list')

# ************** 包管理器安装应对的包名 ************** #
# 此配置需要与包管理器命令顺序一至，配置规则：
# 1、当各包管理器对应的工具名相同时只需要配置一个
# 2、只有部分包管理器需要安装时，其它对应的工具名指定为 "-"

# 安装xz压缩工具
XZ_PACKGE_NAMES=('xz' 'xz-utils')
# 安装unzip解压工具
UNZIP_PACKGE_NAMES=('unzip')
# 安装libtool
LIBTOOL_PACKGE_NAMES=('libtool')
# 安装openssl
OPENSSL_DEVEL_PACKGE_NAMES=('openssl-devel' 'libssl-dev')
# 安装zlib
ZLIB_DEVEL_PACKGE_NAMES=('zlib-devel' 'zlib1g.dev')
# 安装pcre
PCRE_DEVEL_PACKGE_NAMES=('pcre-devel' 'libpcre3-dev')
# 安装ca证书
CA_CERT_PACKGE_NAMES=('ca-certificates')
# 安装CURL
CURL_DEVEL_PACKGE_NAMES=('curl-devel' 'libcurl4-openssl-dev')
# 安装png
PNG_DEVEL_PACKGE_NAMES=('libpng-devel' 'libpng-dev')
# 安装gmp高精度运算
GMP_DEVEL_PACKGE_NAMES=('gmp-devel' 'libgmp-dev')
# 安装jpeg
JPEG_DEVEL_PACKGE_NAMES=('libjpeg-devel' 'libjpeg-dev')
# 安装zip
ZIP_DEVEL_PACKGE_NAMES=('libzip-devel' 'libzip-dev')
# 安装python
PYTHON_DEVEL_PACKGE_NAMES=('python-devel' 'python-dev')
# 安装xml2
LIBXML2_DEVEL_PACKGE_NAMES=('libxml2-devel' 'libxml2-dev')
# 安装freetype
FREETYPE_DEVEL_PACKGE_NAMES=('freetype-devel' 'libfreetype6-dev')
# 安装 oniguruma
ONIGURUMA_DEVEL_PACKGE_NAMES=('oniguruma-devel' 'libonig-dev')
# 安装mcrypt
LIBMCRYPT_DEVEL_PACKGE_NAMES=('libmcrypt-devel' 'libmcrypt-dev')
# 安装tcl
TCL_PACKGE_NAMES=('tcl')
# 安装perl
PERL_DEVEL_PACKGE_NAMES=('perl-devel' 'perl-dev')
# 安装apr
APR_DEVEL_PACKGE_NAMES=('apr-devel' 'libapr1-dev')
# 安装apr-util
APR_UTIL_DEVEL_PACKGE_NAMES=('apr-util-devel' 'libapr1-util-dev')
# 安装sqlite
SQLITE_DEVEL_PACKGE_NAMES=('sqlite-devel' 'sqlite-dev')
# 安装gcc-c++
GCC_C_PACKGE_NAMES=('gcc-c++')
# 安装bzip2
BZIP2_PACKGE_NAMES=('bzip2')
# 安装m4
M4_PACKGE_NAMES=('m4')
# 安装autoconf
AUTOCONF_PACKGE_NAMES=('autoconf')
# 安装jemalloc
JEMALLOC_DEVEL_PACKGE_NAMES=('jemalloc-devel' 'libjemalloc-dev')
# 安装libedit
LIBEDIT_DEVEL_PACKGE_NAMES=('libedit-devel' 'libedit-dev')
# 安装libunwind
LIBUWIND_DEVEL_PACKGE_NAMES=('libunwind-devel' '-')
# 安装ncurses
NCURSES_DEVEL_PACKGE_NAMES=('ncurses-devel' 'libncurses-dev')
# 安装pkgconfig
PKGCONFIG_PACKGE_NAMES=('pkgconfig' 'pkg-config')
# 安装python3
PYTHON3_DOCUTILS_PACKGE_NAMES=('-' 'python3-docutils')
# 安装python3
PYTHON3_SPHINX_PACKGE_NAMES=('-' 'python3-sphinx')
# 安装python-docutils
PYTHON_DOCUTILS_PACKGE_NAMES=('python-docutils')
# 安装python-sphinx
PYTHON_SPHINX_PACKGE_NAMES=('python-sphinx')
