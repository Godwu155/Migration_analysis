# Migration Analysis

欧亚杓鹬（*Numenius arquata*）迁徙行为建模、停歇地识别与保护价值评估项目。

本项目围绕 Movebank GPS 轨迹、ERA5 气象数据和 MODIS NDVI 资源数据，构建从轨迹清洗、环境变量匹配、HMM 行为状态识别、停歇地聚类、停歇时长建模，到资源情景模拟和停歇地保护价值排序的完整分析流程。

## 项目内容

核心分析问题包括：

- 将原始 GPS 轨迹清洗并规则化为近似 1 小时间隔序列。
- 匹配温度、风场、风支持度和 NDVI 等环境变量。
- 使用 HMM 将轨迹点划分为停歇、局部活动、中距离移动和高速飞行等行为状态。
- 基于行为状态和空间聚类识别停歇地或关键活动热点。
- 检验飞行步长是否具有重尾或 Levy-like 特征。
- 建立停歇时长与资源质量、风支持之间的探索性模型。
- 模拟 NDVI 变化情景下停歇时长的潜在变化。
- 计算 SCVI（Stopover Conservation Value Index）用于候选停歇地保护优先级排序。

## 目录结构

```text
.
|-- R/                    # R 主分析脚本
|-- py/                   # Python 环境匹配、Levy 分析和情景投影脚本
|-- scripts/              # 一键运行或分段运行脚本
|-- config/               # 项目参数配置
|-- docs/                 # 流程说明、结果解释和重构记录
|-- paper/                # 论文草稿和结果撰写材料
|-- predictor_app/        # 轨迹/状态预测 Shiny 应用
|-- results_app/          # 只读结果查看 Shiny 应用
|-- viewer_app/           # 轨迹结果查看应用
|-- presentation_work/    # 报告幻灯片生成脚本
`-- app.R                 # 根目录 Shiny 应用入口
```

数据、模型和生成结果未纳入 GitHub 仓库，主要包括：

- `data/`
- `output/`
- `.RData*`
- 原始压缩包和大型 NetCDF/CSV/RDS 文件
- `presentation_work/node_modules/`
- LaTeX、PPT 和其他构建产物

这些文件体积较大或可再生成，应在本地准备或通过外部数据归档管理。

## 环境依赖

R 侧主要依赖：

```r
install.packages(c(
  "readr", "dplyr", "lubridate", "jsonlite", "geosphere",
  "amt", "sf", "purrr", "tibble", "moveHMM", "ggplot2",
  "broom", "tidyr", "scales", "shiny", "leaflet"
))
```

Python 侧主要依赖：

```bash
pip install numpy pandas xarray scikit-learn scipy netCDF4
```

项目使用 Bash 脚本串联完整流程；Windows 环境可通过 Git Bash、WSL 或逐步运行对应 R/Python 脚本。

## 数据准备

运行分析前，需要在本地准备以下数据：

```text
data/raw/curlew_raw.csv
data/raw/CURLEW_VLAANDEREN - Eurasian curlews (Numenius arquata, Scolopacidae)NVDI.csv
data/climate/*.nc
```

关键参数位于：

```text
config/project_config.json
```

其中包含物种代码、清洗阈值、规则化间隔、HMM 候选状态数和停歇地聚类参数。

## 运行流程

完整 A-F 分析流程可通过：

```bash
bash scripts/run_all.sh
```

也可以分段运行：

```bash
Rscript scripts/run_preprocess.R
Rscript scripts/run_hmm.R
```

或直接运行单个脚本，例如：

```bash
Rscript R/02_check_raw.R
python py/05_match_era5.py --project-root .
Rscript R/07_fit_hmm_models.R
python py/09_levy_stopovers.py --project-root .
Rscript R/12_scvi_conservation_value.R
```

主要输出会写入：

```text
data/clean/
data/processed/
output/tables/
output/figures/
output/models/
```

## 应用入口

运行综合 Shiny 应用：

```r
shiny::runApp(".")
```

运行只读结果查看器：

```r
shiny::runApp("results_app")
```

运行预测应用：

```r
shiny::runApp("predictor_app")
```

这些应用依赖本地已生成的数据和结果文件。

## 结果解释注意事项

当前项目中较稳健的部分是轨迹清洗、环境变量匹配、HMM 行为状态划分和基于状态的活动热点识别。

停歇时长模型、NDVI 情景模拟和 SCVI 排序属于探索性分析。它们适合用于提出保护候选区和后续研究假设，但不宜直接解释为强因果证据或最终保护决策。

尤其需要注意：

- HMM 状态解释依赖步长、转角和模型选择结果。
- 空间聚类结果更稳妥地表述为关键活动热点或候选停歇地。
- Levy-like 分析只支持重尾特征探索，不应过度宣称严格 Levy flight。
- 停歇时长模型样本量有限，资源和风支持效应应谨慎解释。
- SCVI 排序依赖权重设定、代理变量和前序模型结果。

## 文档

更多说明见：

- `docs/analysis_workflow.md`
- `docs/result_interpretation.md`
- `docs/prediction_web_app.md`
- `paper/full_paper_draft.md`

## 仓库说明

本仓库用于保存可复现分析代码、项目文档、论文草稿和应用脚本。大型数据、模型对象和运行产物通过 `.gitignore` 排除，不随代码仓库上传。
