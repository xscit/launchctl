#!/bin/zsh

set -e

# 配置目录
config_dir="$HOME/.config/brew_auto_upgrade"
mkdir -p "$config_dir"

# 创建日志目录
log_dir="$config_dir/log"
mkdir -p "$log_dir"

# 检查expect是否安装
if ! command -v expect &> /dev/null; then
  echo "expect未安装。请先安装expect，然后再运行此脚本。"
  exit 1
fi

# 删除现有钥匙串条目（如果存在）
security delete-generic-password -a "$USER" -s brew_upgrade &>/dev/null || true

# 提示用户输入密码
echo "请输入密码以存储在钥匙串中:"
read -s password

# 将密码添加到钥匙串
security add-generic-password -a "$USER" -s brew_upgrade -w "$password"

# 创建expect脚本路径
expect_script_path="$config_dir/brew_auto_upgrade"

# 创建launchd plist文件路径
plist_file_path="$HOME/Library/LaunchAgents/com.whoami.brewupgrade.plist"

# 卸载现有服务（如果存在）
launchctl unload "$plist_file_path" &>/dev/null || true

# 创建expect脚本
cat > "$expect_script_path" <<EOL
#!/usr/bin/expect -f

#日志
log_file $log_dir/brew_auto_upgrade.log

# Start Timestamp
set start [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
send_log "\$start: ----------------------START----------------------\n"

# 获取密码
set password [exec security find-generic-password -a $USER -s brew_upgrade -w]

# Upgrade
spawn $HOMEBREW_PREFIX/bin/brew upgrade --greedy --quiet
expect {
    "Password:" {
        send "\$password\r"
        exp_continue
    }
    eof 
}

# Cleanup
spawn $HOMEBREW_PREFIX/bin/brew cleanup --prune=all
expect eof

# End Timestamp
set end [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
send_log "\$end: -----------------------END-----------------------\n"
EOL

# 使expect脚本可执行
chmod +x "$expect_script_path"

# 创建launchd plist文件
cat > "$plist_file_path" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.whoami.brewupgrade</string>
    <key>ProgramArguments</key>
    <array>
        <string>$expect_script_path</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOL

# 检查 plist 文件是否成功创建
if [ $? -ne 0 ]; then
    echo "错误: 无法创建 plist 文件。"
    exit 1
fi

# 加载和启动服务
launchctl load "$plist_file_path"

echo "任务已成功安排！每六个小时将自动运行brew upgrade和brew cleanup。"