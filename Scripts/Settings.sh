#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
#sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

if grep -q "zn_m2=y" .config; then
		sed -i  \
		        -e 's/[[:space:]]*\<automount\>[[:space:]]*/ /g' \
		        -e 's/[[:space:]]*\<f2fs-tools\>[[:space:]]*/ /g' \
		        -e 's/[[:space:]]*\<e2fsprogs\>[[:space:]]*/ /g' \
		        -e 's/[[:space:]]*\<kmod-usb[^[:space:]]*\>[[:space:]]*/ /g' \
		        -e 's/[[:space:]]*\<kmod-fs[^[:space:]]*\>[[:space:]]*/ /g' \
		        target/linux/qualcommax/Makefile
    if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
        sed -i '/DEVICE_PACKAGES := ipq-wifi-zn_m2/s/^/#/' target/linux/qualcommax/image/ipq60xx.mk
		sed -i 's/[[:space:]]*\<ath11k-firmware-ipq6018[^[:space:]]*\>[[:space:]]*/ /g' target/linux/qualcommax/ipq60xx/target.mk
		sed -i \
		    -e 's/\<kmod-ath11k[^[:space:]]*\>[[:space:]]*//g' \
		    -e 's/\<wpad-openssl\>[[:space:]]*//g' \
			-e 's/\<kmod-qca-nss-drv-wifi-meshmgr\>[[:space:]]*/ /g' \
		    target/linux/qualcommax/Makefile
    fi
fi

if grep -qE '^CONFIG_TARGET_.*_DEVICE_.*040g.*=y' .config; then
	if [[ "${WRT_CONFIG,,}" == *"384"* ]]; then
		echo "WRT_WIFI=384MB" >> $GITHUB_ENV
	
	elif  [[ "${WRT_CONFIG,,}" == *"438"* ]]; then
#        curl -L https://github.com/unless/immortalwrt/commit/ca7137486af261344e8ae99c73d2451aa18467f6.patch | patch -p1 # cpufreq
		curl -L https://raw.githubusercontent.com/unless/OpenWRT-CI/main/Scripts/add-wan.patch | patch -p1 # addwan
		curl -L https://github.com/openwrt/openwrt/pull/24265.patch | patch -p1 # cpufreq
		curl -L https://raw.githubusercontent.com/unless/OpenWRT-CI/main/Scripts/add-438mb-dts.patch | patch -p1 #438mb
		echo "WRT_WIFI=438MB" >> $GITHUB_ENV
	fi
fi

# 1. 提取 TARGET_DIR 与 VERSION_REPO
TARGET_DIR=$(sed -n 's/^CONFIG_TARGET_\(.*\)_DEVICE_.*$/\1/p' .config | sed 's/_/\//g')
VERSION_REPO=$(sed -n 's/^VERSION_REPO:=.*\(https[^)]*\).*/\1/p' include/version.mk)
KMOD_URL="$VERSION_REPO/targets/$TARGET_DIR/kmods/"

# 2. 获取完整内核版本
KERNEL_BASE=$(basename target/linux/$TARGET_DIR/config-* | sed 's/config-//')
PATCH_VER=$(sed -n "s/^LINUX_VERSION-$KERNEL_BASE = //p" target/linux/generic/kernel-$KERNEL_BASE)
FULL_VER="$KERNEL_BASE$PATCH_VER"

# 3. 匹配远程目录
dir_name=$(wget -qO- "$KMOD_URL" | grep -o "${FULL_VER}-[0-9]\+-[0-9a-f]\{32\}/" | tail -1)

if [ -n "$dir_name" ]; then
    sed -i "s/^LINUX_RELEASE.*/LINUX_RELEASE:=$(echo "$dir_name" | cut -d'-' -f2)/" include/kernel-version.mk
    echo "$dir_name" | cut -d'-' -f3 | tr -d '/' > .vermagic
    sed -i $'/vermagic/c\\\t[ -f $(TOPDIR)/.vermagic ] && cat $(TOPDIR)/.vermagic > $(LINUX_DIR)/.vermagic || grep '\''=[ym]'\'' $(LINUX_DIR)/.config.set | LC_ALL=C sort | $(MKHASH) md5 > $(LINUX_DIR)/.vermagic' include/kernel-defaults.mk
    sed -i "s/\$(if \$(CONFIG_BUILDBOT)/\$(if 1/" include/feeds.mk
    echo "成功匹配内核 $FULL_VER-$(echo "$dir_name" | cut -d'-' -f2) 的 md5 校验码：$(cat .vermagic)"
 else
    echo "错误: 未找到与内核版本 $FULL_VER 匹配的预编译 kmod 目录"
fi
