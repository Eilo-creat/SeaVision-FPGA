# SeaVision V1.6.4 — 工程与模块索引

**硬件**：安路 PH1P35MDG324／HX1P35A；SC520CS 摄像头；DDR 帧缓存；HDMI。

**版本说明**：V1.6.4 在原 SVM/P 展示链中增加无有效海胆目标时归零的显示逻辑，原分类器及识别算法未改变。

## 核心模块目录

### 01 视频采集与顶层集成

| 源文件 | 作用 |
|---|---|
| `design_top_wrapper.v` | 顶层接口及多模块互连 |
| `video_in.v` | DDR写帧接口 |
| `video_out.v` | DDR读帧与视频输出 |
| `hdmi_mixer.v` | 图像/文字/检测框合成 |

### 02 图像预处理与增强

| 源文件 | 作用 |
|---|---|
| `seavision_b2_video_bridge.v` | 视频格式与增强链路 |
| `seavision_adaptive_tone.v` | 自适应色调 |
| `seavision_exposure_meter.v` | 曝光反馈测光 |
| `seavision_awb_gain_divider.v` | 白平衡辅助计算 |

### 03 海胆识别与SVM

| 源文件 | 作用 |
|---|---|
| `seavision_urchin_stream_tap.v` | 候选输入及采样 |
| `seavision_urchin_detector_lite.v` | 暗区筛选、RLE连通区域、四特征SVM及外接框 |

### 04 粉色物块识别

| 源文件 | 作用 |
|---|---|
| `seavision_pink_stream.v` | 颜色目标输入 |
| `seavision_pink_regions.v` | 颜色候选与区域统计 |
| `seavision_pink_tracker.v` | 追踪数据输出 |

### 05 显示模式与OSD

| 源文件 | 作用 |
|---|---|
| `seavision_hdmi_display_modes.v` | RAW WB、EDGE、GRAY、BINARY显示 |
| `seavision_mode_osd.v` | 模式、坐标、目标状态、SVM得分等文字叠加 |

### 06 延迟与数码管

| 源文件 | 作用 |
|---|---|
| `seavision_frame_latency.v` | DDR至HDMI数据通路计时 |
| `seavision_sevenseg_latency.v` | 板载毫秒显示 |
| `seavision_sevenseg_cycles.v` | 周期显示 |

### 07 预留研究模块

| 源文件 | 作用 |
|---|---|
| `seavision_structure15.v` | 保留的15特征相关源码（非当前四维SVM有效路径） |
| `seavision_urchin_svm15.v` | 保留的15维SVM源码（非当前四维SVM有效路径） |

## 工程目录说明

- `user_source/hdl_source/`：全部 HDL 工程源文件，包括官方配套模块与用户扩展模块。
- `user_source/ip_source/`：配套 IP 工程文件及生成配置。
- `user_source/constraints_source/`：设备约束。
- `td_project/`：TD IDE 工程、约束、历史综合及布局布线中间结果。
- `offline_evaluation/`：离线核查脚本与分析数据。
- `validation_v164/`：V1.6.4 现有模块级测试记录。
- `source_filename_map.csv`：历史中文文件名与英文文件名对应。

## 当前验证边界

V1.6.4 的 OSD 模块已完成独立 RTL 检查；所附日志记录全工程展开存在 `seavision_hdmi_display_modes` 黑盒错误。因此本工程当前**不能宣称已完成 V1.6.4 全工程布局布线与实板测试**，同时本包**不包含 V1.6.4 新生成的烧录 bit 文件**。提交前应在实际 TD 环境排查工程文件引用、重新综合/布局布线并上板验收。

历史版本记录仅供追溯，以 `00_README_V164.txt` 和当前 HDL 为最新依据。

## 代码说明

工程内 HDL 文件保持原样，没有为提交而插入逐行注释，也没有改写判别逻辑。模块用途统一列于本文档。
