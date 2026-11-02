# 构建与验证

## 开发环境

- HX1P35A / PH1P35MDG324
- SC520CS MIPI 摄像头、HDMI 显示器
- 安路 TD IDE（原工程记录使用 6.2）

## 工程恢复

1. 从有授权来源取得官方工程/厂商 IP；按 `VENDOR_DEPENDENCIES.md` 放回原目录。
2. 从比赛存档工程恢复 `design_top_wrapper.v`、`hdmi_mixer.v` 及 TD 项目配置。
3. 把本仓库 `user_source/hdl_source/` 中 SeaVision 模块加入现有工程。
4. 在 TD IDE 修复路径后重新执行综合、布局布线、Bitstream 生成和实板测试。

此仓库是可公开核查的功能源码，不是自包含的、无厂商依赖的可直接编译工程。

## V1.6.4 验证状态

V1.6.4 为界面变更：未检测到海胆时，在相应显示模式下 `SVM:0.00`、`P:00.0%`。上传包中的验证日志记录了 OSD 单模块 RTL 检查成功，但全工程展开发现 `seavision_hdmi_display_modes` 黑盒错误。未提供 V1.6.4 上板/最终时序结果。本仓库不能据此宣称 V1.6.4 已全部验证。

图像为此前 V1.6.3 实机演示材料，非 V1.6.4 实机证据。
