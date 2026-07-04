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
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

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

#daed内核配置
if grep -q "^CONFIG_PACKAGE_daed=y" .config; then
    BOARD=$(grep -oP '^CONFIG_TARGET_BOARD="\K[^"]+' .config)
    SUBTARGET=$(grep -oP '^CONFIG_TARGET_SUBTARGET="\K[^"]+' .config)
    # 如果变量未定义，从选中的target符号中提取（fallback）
    if [ -z "$BOARD" ]; then
        TARGET_SYM=$(grep -oP '^CONFIG_TARGET_\K[^=]+(?==y)' .config | grep '_' | head -1)
        BOARD=${TARGET_SYM%_*}
        SUBTARGET=${TARGET_SYM#*_}
    fi
    KERNEL_CONFIG_DIR="target/linux/$BOARD${SUBTARGET:+/$SUBTARGET}"
    KERNEL_CONFIG_FILE=$(find "$KERNEL_CONFIG_DIR" -maxdepth 1 -type f -name "config-*" 2>/dev/null | head -1)
    grep -q "^# CONFIG_ARM64_BRBE is not set" "$KERNEL_CONFIG_FILE" || echo "# CONFIG_ARM64_BRBE is not set" >> "$KERNEL_CONFIG_FILE"
fi

if grep -qE '^CONFIG_TARGET_.*_DEVICE_.*040g.*=y' .config; then
    echo "Device with 040g selected, patching network config"
        sed -i '/nokia,xg-040g-md/,/;;/ {
            s/^\([[:space:]]*\)ucidef_set_interface_lan "lan1 lan2 lan3 lan4"[[:space:]]*$/\1ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "lan4"/
        }' target/linux/airoha/an7581/base-files/etc/board.d/02_network
fi
