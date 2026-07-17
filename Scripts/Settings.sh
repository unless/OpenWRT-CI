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
		sed -i '/^DEFAULT_PACKAGES += ath11k-firmware-ipq6018-ddwrt/s/^/#/' target/linux/qualcommax/ipq60xx/target.mk
		sed -i  \
		  -e 's/\<kmod-ath11k-ahb\>[[:space:]]*//g' \
		  -e 's/\<kmod-ath11k-pci\>[[:space:]]*//g' \
		  -e 's/\<kmod-ath11k\>[[:space:]]*//g' \
		  -e 's/\<wpad-openssl\>[[:space:]]*//g' \
		  -e 's/\<kmod-usb3\>[[:space:]]*//g' \
		  -e 's/\<kmod-usb-dwc3-qcom\>[[:space:]]*//g' \
		  -e 's/\<kmod-usb-serial-qualcomm\>[[:space:]]*//g' \
		  -e 's/\<kmod-usb-dwc3\>[[:space:]]*//g' \
		  -e 's/\<kmod-fs-ext4\>[[:space:]]*//g' \
		  -e 's/\<kmod-fs-f2fs\>[[:space:]]*//g' \
		  target/linux/qualcommax/Makefile
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

if grep -qE '^CONFIG_TARGET_.*_DEVICE_.*040g.*=y' .config; then
	if [[ "${WRT_CONFIG,,}" == *"384"* ]]; then
		echo "WRT_WIFI=384MB" >> $GITHUB_ENV
	
	elif  [[ "${WRT_CONFIG,,}" == *"438"* ]]; then
		curl -L https://github.com/unless/immortalwrt/commit/39c517de8c32081b3a26578f8030b87b1b2c9340.patch -o /tmp/add-wan.patch
		patch -p1 < /tmp/add-wan.patch
        curl -L https://github.com/unless/immortalwrt/commit/ca7137486af261344e8ae99c73d2451aa18467f6.patch -o /tmp/fix-cpufreq.patch
        patch -p1 < /tmp/fix-cpufreq.patch
        curl -L https://github.com/unless/immortalwrt/commit/806a9955cc4d8fc3dc575d7c7c858adb03cb16ad.patch -o /tmp/add-438mb-dts.patch
        patch -p1 < /tmp/add-438mb-dts.patch
		echo "WRT_WIFI=438MB" >> $GITHUB_ENV
	fi
fi

TARGET_DIR=$(sed -n 's/^CONFIG_TARGET_\(.*\)_DEVICE_.*$/\1/p' .config | sed 's/_/\//g')
echo $TARGET_DIR
VERSION_REPO=$(sed -n 's/^VERSION_REPO:=.*\(https[^)]*\).*/\1/p' include/version.mk)
echo $VERSION_REPO
KMOD_URL="$VERSION_REPO/targets/$TARGET_DIR/kmods/"
echo $KMOD_URL
hash_value=$(wget -qO- "$KMOD_URL" | grep -o '[0-9a-f]\{32\}' | tail -1)
echo $hash_value
if [[ "$hash_value" =~ ^[0-9a-f]{32}$ ]]; then
    echo "$hash_value" > .vermagic
    echo "kernel内核md5校验码：$hash_value"
else
    echo "未找到有效的 kernel hash"
fi
