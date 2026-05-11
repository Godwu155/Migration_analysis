
# 项目说明：欧亚杓鹬迁徙行为建模与停歇地保育评估
## 研究目标

本项目以 Movebank 数据集 CURLEW_VLAANDEREN 中的欧亚杓鹬轨迹为对象，构建从轨迹预处理、行为状态识别、飞行步长分布检验、停歇地识别、最优停止建模、气候/资源情景模拟到停歇地保育价值排序的完整分析流程。

## 当前研究对象

- 物种：欧亚杓鹬 Numenius arquata
- 个体数：5
- 轨迹数据来源：Movebank
- 环境数据：ERA5 温度与风场，MODIS NDVI
- 主要分析语言：R + Python

## 已完成模块

### A 数据预处理与环境匹配

- 清洗原始 GPS 轨迹
- 严格 1 小时规则化
- 匹配 ERA5 温度、u/v 风分量
- 计算 wind_speed 和 wind_support
- 匹配 MODIS NDVI

关键输出：
- data/clean/curlew_regular.csv
- data/clean/curlew_env_matched.csv

### B HMM 行为状态识别

使用 moveHMM 基于 step length 和 turning angle 拟合 2、3、4 状态模型，并用 BIC 选择最优状态数。

结果：
- 4 状态模型最优
- 状态解释为：
  1. 停歇
  2. 局部活动/觅食
  3. 中距离移动
  4. 高速飞行

关键输出：
- data/processed/curlew_hmm_input.rds
- data/processed/curlew_states_decoded.csv
- output/tables/08_state_summary.csv
- output/figures/08_state_tracks.png

### C Lévy 分析与停歇地识别

基于高速飞行状态进行步长分布拟合，并用 DBSCAN 从停歇/局部活动状态中识别停歇地。

Lévy 结果：
- alpha = 2.381495
- xmin = 1.298588
- R_lognormal = -171.363333
- p_lognormal = 4.240205e-35
- R_exponential = -80.331941
- p_exponential = 0.005153

解释：
- 高速飞行步长具有重尾特征
- 但对数正态和指数模型优于纯幂律
- 因此不能声称严格支持 Lévy 飞行

停歇地：
- 共识别 33 个停歇地事件

关键输出：
- data/processed/curlew_levy_result.csv
- data/processed/curlew_stopovers.csv

### D 最优停止/停歇时长模型

使用到达时 NDVI 作为资源质量代理变量，使用 wind_support 作为风支持变量，建模停留时长。

敏感性模型结果：
- n = 22
- resource_z = 0.038, p = 0.891
- wind_z = 0.220, p = 0.432
- R² = 0.0219
- RMSE = 40.1
- lambda_proxy = 0.0253
- Qstar_proxy = 0.478

解释：
- NDVI 和风支持方向为正，但不显著
- 当前数据未能强支持最优停止假说
- 结果应解释为探索性

关键输出：
- output/tables/10_optimal_stopping_lm_coefficients.csv
- output/tables/10_optimal_stopping_predictions.csv
- output/tables/10_stopovers_qc.csv

### E 气候/资源情景模拟

基于 D 模块代理参数，模拟不同 NDVI 变化情景下预测停留时长变化。

结果：
- 当前 NDVI：平均预测停留 7.54 h
- NDVI 下降 5%：6.01 h
- NDVI 下降 10%：4.69 h
- NDVI 下降 20%：2.34 h
- NDVI 上升 5%：9.12 h

解释：
- NDVI 下降可能压缩有效补给时间
- 但由于 D 模型解释度低，属于探索性情景模拟

关键输出：
- output/tables/11_climate_scenario_projection.csv
- output/tables/11_climate_scenario_summary.csv
- output/figures/11_climate_scenario_projection.png

### F SCVI 停歇地保育价值指数

整合使用强度、停留时长、资源质量和气候脆弱性，构建 SCVI。

结果：
- 参与排序停歇地：33 个
- 高优先级：7 个
- 中优先级：10 个
- 低优先级：16 个
- SCVI 最高值：0.772
- SCVI 中位数：0.451

解释：
- 当前 SCVI 更适合解释为关键活动地点综合保育价值指数
- 由于部分地点停留时间极长，不完全等同于狭义迁徙停歇地排序

关键输出：
- output/tables/12_scvi_stopover_ranking.csv
- output/tables/12_project_result_summary.csv
- output/figures/12_scvi_ranking_bar.png
- output/figures/12_scvi_stopover_map.png

## 希望 Codex 完成的任务

请阅读整个项目代码和输出结果，完成以下工作：

1. 梳理项目完整分析流程；
2. 解释每个脚本的作用、输入和输出；
3. 检查代码流程是否存在明显逻辑问题；
4. 根据 output/tables 和 output/figures 中的结果，撰写一份中文项目结果解释；
5. 生成一份论文结果部分初稿；
6. 对哪些结果可以强解释、哪些结果只能探索性解释进行区分；
7. 给出后续改进建议。