# DesktopIconFixer - 一键修复桌面图标

Windows 桌面图标"消失"、变空白、快捷方式点不开?这个小工具一键搞定。

它解决了两类最常见的桌面图标问题:

1. **图标缓存损坏** —— 程序明明还在,快捷方式也在,但图标显示成空白或默认样式;
2. **快捷方式失效** —— 软件升级/移动目录后,快捷方式还指向旧路径(如 `D:\App\XXX\7.0.0\` 升级到 `7.1.0`),图标丢失、双击无反应。

## 功能

- 扫描**当前用户桌面**和**公共桌面**(Public Desktop)的全部快捷方式
- 自动检测两类问题:
  - 目标 exe 已不存在的失效快捷方式
  - 图标引用(`IconLocation`)指向的文件已不存在
- 失效快捷方式自动找回新目标,按优先级搜索:
  1. 旧目标附近的祖先目录递归查找同名 exe(覆盖"版本号目录升级"这一最常见场景)
  2. 开始菜单中的同名快捷方式
  3. 注册表卸载信息(DisplayIcon / InstallLocation)
  4. `%LOCALAPPDATA%\Programs` 等常见安装位置
- 修复后同步更新工作目录与图标引用(改用程序本体图标)
- 重建 Windows 图标缓存(删除 `IconCache.db` / `iconcache_*.db` 并重启资源管理器)
- 输出彩色汇总报告

## 使用方法

### 方式一:双击运行(推荐)

直接双击 `一键修复桌面图标.bat`。

### 方式二:仅诊断,不做修改

```bat
一键修复桌面图标.bat -ScanOnly
```

或:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Fix-DesktopIcons.ps1 -ScanOnly
```

### 方式三:直接运行 PowerShell 脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Fix-DesktopIcons.ps1
```

> 也可以把 bat 创建为桌面快捷方式,随时一键运行。

## 注意事项

- 修复模式最后会**结束并重启资源管理器**(explorer.exe),桌面和任务栏会闪烁一下,属正常现象;
- 对"软件已卸载"或"产品改名换了主程序"的快捷方式,工具**不会盲猜目标**(注册表中的 DisplayIcon 经常指向卸载器等非主程序,自动修改有指错风险),只会在报告中列出,请人工确认;
- 系统/应用对象快捷方式(如此电脑、UWP 应用)会自动跳过;
- 扫描范围有深度限制(祖先目录递归深度 4),不会全盘扫描,单次运行通常几十秒内完成。

## 环境要求

- Windows 10 / 11
- Windows PowerShell 5.1+(系统自带,无需额外安装)

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `Fix-DesktopIcons.ps1` | 核心脚本 |
| `一键修复桌面图标.bat` | 双击入口(内部调用上面的 ps1) |

## 许可证

[MIT](LICENSE)
