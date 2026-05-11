# 欧亚杓鹬迁徙行为与停歇地保育价值分析流程

本文档梳理当前项目代码库中的完整分析链条。项目以 Movebank 中欧亚杓鹬（*Numenius arquata*）GPS 轨迹为核心数据，逐步完成轨迹预处理、环境变量匹配、行为状态识别、停歇地识别、停歇时长建模、资源情景模拟和保育价值排序。

## 1. 项目总体流程图的文字版

原始 Movebank GPS 轨迹  
-> 轨迹列名标准化、时间解析、异常速度过滤、重复点删除  
-> 规则化或插值到近似 1 小时时间分辨率  
-> 匹配 ERA5 温度和风场变量  
-> 匹配 MODIS NDVI 资源变量  
-> 构建 HMM 输入数据，计算步长和转角  
-> 拟合 2、3、4 状态 HMM，并用 BIC 选择最佳模型  
-> Viterbi 解码行为状态  
-> 基于飞行状态步长进行 Lévy/重尾分布检验  
-> 基于停歇和局部活动状态点用 DBSCAN 识别停歇地或关键活动地  
-> 回填每个停歇地的 NDVI、风支持和停留时长  
-> 建立停歇时长与资源、风支持之间的经验模型  
-> 基于 NDVI 变化设定资源情景，模拟预测停留时长变化  
-> 综合使用强度、停留时长、资源质量和气候脆弱性，计算 SCVI 保育价值指数  
-> 输出停歇地保育优先级排序、图表和项目结论。

## 2. A 模块：数据清洗与规则化

### 研究作用

A 模块负责把原始 Movebank 轨迹转化为后续行为建模可用的时空序列。它解决三个基础问题：坐标和时间字段是否可识别，异常速度和重复记录是否被剔除，轨迹是否可以转换为规则或近规则的 1 小时时间间隔，并为每个轨迹点补充环境变量。

### 输入文件

- `data/raw/curlew_raw.csv`：原始欧亚杓鹬 GPS 轨迹。
- `data/raw/CURLEW_VLAANDEREN - Eurasian curlews (Numenius arquata, Scolopacidae)NVDI.csv`：Movebank/MODIS NDVI 数据。
- `data/climate/*.nc`：ERA5 温度和风场 NetCDF 文件。
- `config/project_config.json`：清洗阈值、物种代码、规则化参数和路径相关配置。

### 核心脚本

- `R/00_config.R`：读取配置并生成统一路径。
- `R/01_utils.R`：提供列名标准化、时间解析、速度计算等工具函数。
- `R/02_check_raw.R`：检查原始数据规模、个体数、时间范围和缺失情况。
- `R/03_clean_tracking.R`：删除缺失、重复点、异常速度点和点数不足个体。
- `R/04_regularize_tracks.R`：使用 `amt` 按 1 小时容差规则化轨迹。
- `R/04b_regularize_interpolate.R`：按 burst 进行严格 1 小时线性插值，是规则化的替代实现。
- `py/05_match_era5.py`：从 ERA5 文件提取温度、u/v 风分量，并计算风速和顺逆风支持。
- `R/05b_match_ndvi.R`：按个体和时间为 GPS 点匹配 NDVI。

### 输出文件

- `output/tables/00_raw_summary.csv`：原始数据摘要。
- `data/clean/curlew_clean.csv`：清洗后的轨迹。
- `output/tables/03_clean_tracking_summary.csv`：个体级清洗摘要。
- `data/clean/curlew_regular.csv`：规则化后的轨迹主表。
- `output/tables/regularize_check.csv`：规则化间隔检查。
- `output/tables/regularize_check_1h.csv`：严格 1 小时插值结果检查。
- `data/clean/curlew_env_matched.csv`：匹配 ERA5 和当前主线 NDVI 后的轨迹表。
- `data/clean/curlew_env_matched_ndvi.csv`：NDVI 匹配脚本的显式输出。
- `output/tables/05b_ndvi_match_qc.csv`：NDVI 匹配总体质控。
- `output/tables/05b_ndvi_match_by_id.csv`：NDVI 匹配个体级质控。

## 3. B 模块：HMM 行为状态识别

### 研究作用

B 模块把规则化后的轨迹转换为行为状态序列。核心思想是使用步长和转角作为观测过程，由 HMM 区分停歇、局部活动、飞行和高速飞行等隐含状态，并允许温度和风支持作为状态转移的协变量。

### 输入文件

- `data/clean/curlew_env_matched.csv`：带温度、风和 NDVI 的规则化轨迹。
- `config/project_config.json`：HMM 候选状态数、最小 burst 长度、最大步长阈值。

### 核心脚本

- `R/06_prepare_hmm_data.R`：按近似 1 小时连续性切分 burst，计算 HMM 所需步长和转角，标准化环境变量。
- `R/07_fit_hmm_models.R`：拟合 2、3、4 状态 HMM，并用 BIC 选择最佳状态数。
- `R/08_decode_hmm.R`：对最佳模型做 Viterbi 解码，按平均步长给状态排序和命名，并绘制状态轨迹图。
- `R/08b_add_ndvi_to_states.R`：把 NDVI 补回状态解码表，便于后续停歇地环境汇总。

### 输出文件

- `data/processed/curlew_hmm_input.csv`：HMM 输入数据。
- `data/processed/curlew_hmm_input.rds`：HMM 输入 RDS。
- `output/models/curlew_hmm_2state.rds`、`curlew_hmm_3state.rds`、`curlew_hmm_4state.rds`：候选 HMM。
- `output/models/curlew_hmm_best.rds`：BIC 最优 HMM。
- `output/tables/06_prepare_hmm_summary.csv`：HMM 输入摘要。
- `output/tables/07_hmm_bic_compare.csv`：不同状态数模型的 AIC/BIC 比较。
- `data/processed/curlew_states_decoded.csv`：Viterbi 状态解码结果。
- `output/tables/08_state_summary.csv`：各状态步长和转角摘要。
- `output/tables/08_transition_matrix.csv`：转移矩阵输出位置。
- `output/figures/08_state_tracks.png`：状态着色轨迹图。

## 4. C 模块：Lévy 分析与停歇地识别

### 研究作用

C 模块回答两个问题。第一，飞行步长是否表现出重尾或 Lévy-like 特征。第二，HMM 识别出的停歇和局部活动状态点在空间上是否形成可解释的停歇地或关键活动地聚类。

### 输入文件

- `data/processed/curlew_states_decoded.csv`：带行为状态、步长、坐标和环境变量的状态序列。
- `config/project_config.json`：DBSCAN 空间半径 `eps_km` 和最小点数 `min_samples`。

### 核心脚本

- `py/09_levy_stopovers.py`：对飞行状态步长拟合 power-law，并与 lognormal、exponential 分布比较；同时用 DBSCAN 在停歇和局部活动状态点中识别空间聚类。
- `R/09b_rebuild_stopovers_env.R`：根据状态表重新回填每个停歇地的 NDVI、到达 NDVI、风支持和状态点数。

### 输出文件

- `data/processed/curlew_levy_result.csv`：Lévy/power-law 拟合与分布比较结果。
- `data/processed/curlew_stopovers.csv`：停歇地或关键活动地聚类表。

## 5. D 模块：最优停止/停歇时长模型

### 研究作用

D 模块尝试解释停歇地停留时长是否与到达时资源质量和风支持有关。这里的“最优停止”更准确地说是经验性停歇时长模型和代理参数估计，而不是严格验证的机制性最优停止模型。

### 输入文件

- `data/processed/curlew_stopovers.csv`：停歇地表，包含停留时长、NDVI、风支持、中心坐标和点数。
- `config/project_config.json`：停歇地最短和最长时长过滤阈值。

### 核心脚本

- `R/10b_stopover_sensitivity.R`：描述停歇时长分布，输出按时长排序的停歇地，并在不同过滤条件下拟合敏感性模型。
- `R/10_optimal_stopping.R`：建立 `log(duration_hr) ~ ndvi_arrive_z + wind_support_z` 的线性模型，生成预测值和代理参数。

### 输出文件

- `output/tables/10b_stopover_duration_summary.csv`：停歇时长分布摘要。
- `output/tables/10b_stopovers_ordered_by_duration.csv`：按停留时长排序的停歇地。
- `output/tables/10b_stopover_subset_counts.csv`：不同过滤子集的样本量。
- `output/tables/10b_stopover_sensitivity_summary.csv`：敏感性模型摘要。
- `output/tables/10b_stopover_sensitivity_coefficients.csv`：敏感性模型系数。
- `output/tables/10_stopovers_qc.csv`：停歇地建模质控。
- `output/tables/10_optimal_stopping_lm_coefficients.csv`：主停歇时长模型系数。
- `output/tables/10_optimal_stopping_params.csv`：代理参数、RMSE 和 R2。
- `output/tables/10_optimal_stopping_predictions.csv`：观测与预测停留时长。
- `output/models/curlew_os_lm.rds`：停歇时长线性模型。
- `output/figures/10b_duration_histogram.png`、`10b_log_duration_histogram.png`、`10b_duration_boxplot.png`：停歇时长分布图。
- `output/figures/10b_ndvi_vs_log_duration.png`：NDVI 与 log 停歇时长关系图。
- `output/figures/10b_wind_vs_log_duration.png`：风支持与 log 停歇时长关系图。
- `output/figures/10_optimal_stopping_pred_obs.png`：预测与观测对比图。

## 6. E 模块：NDVI 情景模拟

### 研究作用

E 模块在 D 模块代理参数基础上，模拟资源质量变化对预测停留时长的潜在影响。它不是直接气候模型投影，而是基于 NDVI 当前值的情景扰动，包括 NDVI 下降 5%、10%、20% 和上升 5%。

### 输入文件

- `data/processed/curlew_stopovers.csv`：停歇地表。
- D 模块中的代理参数：当前 R 脚本内硬编码使用 `lambda_proxy` 和 `Qstar_proxy`。

### 核心脚本

- `R/11_climate_scenario_projection.R`：基于 NDVI 情景倍率计算预测停留时长变化和风险等级。
- `py/11_climate_projection.py`：较早的 CMIP6/NetCDF 投影骨架脚本，当前不属于主要 A-F 结果链条。

### 输出文件

- `output/tables/11_climate_scenario_projection.csv`：每个停歇地在各 NDVI 情景下的预测结果。
- `output/tables/11_climate_scenario_summary.csv`：各情景汇总结果。
- `output/figures/11_climate_scenario_projection.png`：NDVI 情景下平均预测停留时长图。

## 7. F 模块：SCVI 保育价值指数

### 研究作用

F 模块把前面得到的空间使用强度、停留时长、资源质量和资源下降情景下的脆弱性整合为 SCVI（Stopover Conservation Value Index）保育价值指数，用于对停歇地或关键活动地进行候选保护优先级排序。

### 输入文件

- `data/processed/curlew_stopovers.csv`：停歇地表。
- `output/tables/11_climate_scenario_projection.csv`：NDVI 情景模拟结果。

### 核心脚本

- `R/12_scvi_conservation_value.R`：计算使用强度得分、停留时长得分、资源质量得分和脆弱性得分，并按预设权重合成为 SCVI。

### 输出文件

- `output/tables/12_scvi_stopover_ranking.csv`：SCVI 停歇地排序表。
- `output/tables/12_project_result_summary.csv`：项目结果汇总。
- `output/figures/12_scvi_ranking_bar.png`：SCVI 排名前列柱状图。
- `output/figures/12_scvi_stopover_map.png`：SCVI 空间分布图。

## 8. 整个项目的科学解释路径

本项目的科学解释路径应从稳健的数据处理结果开始，而不是直接从保育排序开始。首先，原始 GPS 数据经过清洗和规则化后，形成可用于行为建模的轨迹序列，并与温度、风场和 NDVI 等环境变量结合。这一步建立了轨迹行为和环境背景之间的共同分析单位。

其次，HMM 模块把连续轨迹转化为离散行为状态。由于状态间平均步长存在清楚梯度，模型可以支持“停歇/局部活动/飞行/高速飞行”这一行为解释框架。这个结果是后续所有停歇地识别和空间解释的基础。

第三，基于 HMM 状态，项目将低移动强度状态点识别为空间聚类，从而得到一组停歇地或关键活动地候选。这里需要注意，当前 DBSCAN 聚类以空间位置为核心，并不严格区分多年重复访问与单次连续停歇事件。因此，科学表述中更稳妥的说法是“关键停歇/活动热点”或“重复利用地点”，而不是把所有聚类都解释为一次迁徙停歇。

第四，项目尝试检验飞行步长是否支持 Lévy-like 运动。当前 power-law 拟合给出了重尾特征，但与 lognormal 和 exponential 的比较结果不支持强烈宣称严格 Lévy flight。因此，该部分适合作为运动步长分布特征的探索性证据。

第五，停歇时长模型把到达 NDVI 和风支持与停留时长联系起来，用于检验资源质量和风场是否可以解释停留决策。当前模型解释度较低、主要系数不显著，因此不能作为强因果证据。更合适的解释是：当前样本和停歇地定义下，尚未发现稳定的资源或风支持效应。

第六，NDVI 情景模拟和 SCVI 排序属于基于前述模型的应用性推演。它们可以帮助生成保护假设和候选优先区，例如哪些地点使用强度高、停留时间长、资源质量较高或在资源下降情景下更脆弱。但由于这些结果依赖代理参数、权重设定和探索性模型，应该作为保育规划的初筛工具，而不是最终保护决策。

因此，项目最稳健的结论链条是：清洗后的欧亚杓鹬轨迹可以被 HMM 分解为具有明确运动强度梯度的行为状态；基于这些状态可以识别出若干重复利用的关键活动地；这些地点可进一步用资源、停留时长和情景脆弱性指标进行探索性保育价值排序。后续若要强化论文结论，应优先把空间聚类拆分为真正的连续停歇事件，完善 NDVI/风场匹配质控，并用更明确的统计模型检验资源和风支持对停留时长的影响。
