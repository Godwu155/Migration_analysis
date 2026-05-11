# 2 数据与方法

## 2.1 研究对象与数据来源

本研究以欧亚杓鹬（*Numenius arquata*）为研究对象，使用 Movebank 数据集 CURLEW_VLAANDEREN 中的 GPS 追踪记录开展迁徙行为状态识别与关键停歇地评估。项目配置文件 `config/project_config.json` 将研究物种代码设为 `curlew`，时间标准统一为 UTC。原始轨迹数据存放于 `data/raw/curlew_raw.csv`，包含个体编号、时间戳、经纬度及 Movebank 附带的传感器字段。根据项目输出表 `output/tables/00_raw_summary.csv`，原始数据共包含 393,845 条记录，覆盖 5 个追踪个体，时间范围为 2020 年 5 月 5 日至 2025 年 10 月 10 日。

环境数据包括 ERA5 再分析温度和风场数据，以及 MODIS NDVI 数据。ERA5 数据以 NetCDF 文件形式存放于 `data/climate/`，包括 2020-2025 年温度和风分量文件。NDVI 原始数据来自 Movebank/MODIS 相关输出，存放于 `data/raw/CURLEW_VLAANDEREN - Eurasian curlews (Numenius arquata, Scolopacidae)NVDI.csv`。本研究将 ERA5 温度和风场用于描述迁徙过程中鸟类所处的气象背景，将 NDVI 作为资源质量的遥感代理变量。需要指出的是，NDVI 并不直接等同于欧亚杓鹬可利用食物资源，而是用于后续停留时长模型、情景模拟和保育价值指数中的探索性资源指标。

整个分析流程由 R 和 Python 脚本共同完成。路径和参数由 `R/00_config.R` 与 `config/project_config.json` 统一管理，通用数据处理函数由 `R/01_utils.R` 提供。各模块的中间数据主要输出至 `data/clean/` 和 `data/processed/`，模型、图件和统计表分别输出至 `output/models/`、`output/figures/` 和 `output/tables/`。

## 2.2 轨迹数据清洗与 1 小时规则化

轨迹预处理首先对原始 Movebank 数据进行字段标准化、时间解析和基础质控。`R/02_check_raw.R` 读取 `data/raw/curlew_raw.csv`，通过 `R/01_utils.R` 中的列名标准化函数识别个体编号、经纬度和时间字段，并将时间解析为 UTC 时间。该步骤输出原始数据摘要表 `output/tables/00_raw_summary.csv`，用于记录原始记录数、个体数、时间范围及关键字段缺失情况。

随后，`R/03_clean_tracking.R` 对轨迹数据进行清洗。清洗流程包括删除时间或坐标缺失记录、删除同一个体在同一时间的重复记录、按个体和时间排序，并基于 haversine 距离计算相邻点移动速度。项目配置中将最大合理速度阈值设为 35 m/s，超过该阈值的记录被视为异常移动点并剔除。清洗后还保留记录数不少于 50 的个体。该步骤输出清洗后的轨迹文件 `data/clean/curlew_clean.csv` 以及个体级清洗摘要 `output/tables/03_clean_tracking_summary.csv`。

为满足后续 HMM 和环境匹配对时间间隔一致性的要求，项目对清洗后的轨迹进行 1 小时规则化。主流程中包含两种规则化实现：`R/04_regularize_tracks.R` 使用 `amt` 包在 1 小时目标间隔和 20 分钟容差内重采样轨迹；`R/04b_regularize_interpolate.R` 则按个体轨迹的时间断裂划分 burst，并在每个 burst 内进行严格 1 小时线性插值。为了避免跨越长时间缺口进行不合理插值，严格插值脚本将超过 3 小时的时间间隔视为新的 burst。规则化检查结果分别输出至 `output/tables/regularize_check.csv` 和 `output/tables/regularize_check_1h.csv`。后续环境匹配和 HMM 分析使用规则化后的轨迹数据，主要文件为 `data/clean/curlew_regular.csv`。

## 2.3 ERA5 风温数据与 MODIS NDVI 匹配

ERA5 风温数据匹配由 `py/05_match_era5.py` 完成。该脚本以规则化轨迹 `data/clean/curlew_regular.csv` 为输入，读取 `data/climate/` 下的 NetCDF 文件，并根据每个 GPS 点的时间和空间位置提取最近 ERA5 网格的环境变量。脚本自动识别 NetCDF 中的时间、纬度、经度坐标名称，以及温度、u 风分量和 v 风分量变量名。若 ERA5 经度坐标采用 0-360 度表示，则将 GPS 经度转换为相应范围后进行匹配。

ERA5 匹配后，脚本将温度由 K 转换为摄氏度，得到 `temp_C`；基于 u、v 分量计算风速 `wind_speed`；同时根据相邻轨迹点计算个体移动方位，并将风矢量投影到移动方向上，得到 `wind_support`。其中，`wind_support` 为正表示顺风支持，为负表示逆风条件。ERA5 匹配结果输出为 `data/clean/curlew_env_matched.csv`，该文件作为后续 NDVI 匹配和 HMM 输入构建的基础。

MODIS NDVI 匹配由 `R/05b_match_ndvi.R` 完成。该脚本以 ERA5 匹配后的轨迹文件 `data/clean/curlew_env_matched.csv` 和 NDVI 原始文件为输入，按个体分别匹配时间最近的 NDVI 观测。项目中设置最大允许时间差为 20 天；若最近 NDVI 记录超过该时间窗口，则该 GPS 点的 NDVI 记为缺失。脚本还根据原始 NDVI 数值范围判断是否需要进行缩放，并将异常范围外的 NDVI 值设为缺失。输出文件为 `data/clean/curlew_env_matched_ndvi.csv`，同时生成总体质控表 `output/tables/05b_ndvi_match_qc.csv` 和个体级质控表 `output/tables/05b_ndvi_match_by_id.csv`。

由于 NDVI 匹配存在缺失和个体间匹配质量差异，本文将 NDVI 作为资源质量代理变量用于探索性建模和保育指标构建，而不将其解释为直接食物资源测量。

## 2.4 HMM 行为状态识别

行为状态识别采用隐马尔可夫模型（Hidden Markov Model, HMM）完成，相关流程由 `R/06_prepare_hmm_data.R`、`R/07_fit_hmm_models.R` 和 `R/08_decode_hmm.R` 实现。HMM 的输入数据来自匹配 ERA5 和 NDVI 后的规则化轨迹。`R/06_prepare_hmm_data.R` 读取 `data/clean/curlew_env_matched_ndvi.csv`，保留时间、坐标、温度、风支持、风速和 NDVI 等字段，并按个体检查相邻点时间间隔。相邻点时间间隔小于 0.9 小时或大于 1.1 小时时，脚本将其视为新的 burst；每个 burst 至少需要包含 10 个点。随后使用 `moveHMM::prepData` 根据经纬度计算步长和转角，并过滤步长超过 120 km 的记录。该步骤输出 `data/processed/curlew_hmm_input.csv` 和 `data/processed/curlew_hmm_input.rds`，并生成输入摘要 `output/tables/06_prepare_hmm_summary.csv`。

HMM 拟合由 `R/07_fit_hmm_models.R` 完成。项目分别拟合 2、3 和 4 状态模型，步长和转角作为观测变量。模型中将标准化温度和标准化风支持作为状态转移协变量，公式为 `~ temp_z + wind_support_z`。各候选模型使用预设初值拟合，随后通过 AIC 和 BIC 进行比较，并以 BIC 最低者作为最佳模型。各状态数模型分别保存为 `output/models/curlew_hmm_2state.rds`、`output/models/curlew_hmm_3state.rds` 和 `output/models/curlew_hmm_4state.rds`，最佳模型保存为 `output/models/curlew_hmm_best.rds`。模型比较结果输出至 `output/tables/07_hmm_bic_compare.csv`。

最佳模型的行为状态解码由 `R/08_decode_hmm.R` 完成。脚本对最佳 HMM 进行 Viterbi 解码，并根据各状态平均步长由小到大为状态赋予生态解释标签。当前项目中状态依次解释为停歇、局部活动/觅食、飞行和高速飞行。解码结果输出至 `data/processed/curlew_states_decoded.csv`，状态步长和转角摘要输出至 `output/tables/08_state_summary.csv`，行为状态空间轨迹图输出至 `output/figures/08_state_tracks.png`。需要强调的是，这些状态标签是基于运动特征的模型解释，而不是地面行为观测的直接验证结果。

为便于后续停歇地环境变量汇总，`R/08b_add_ndvi_to_states.R` 将 NDVI 相关字段从环境匹配表重新补入状态解码表，输出为 `data/processed/curlew_states_decoded_env.csv`，并生成 NDVI 回填质控表。

## 2.5 Lévy 步长分布分析

飞行步长分布分析由 `py/09_levy_stopovers.py` 完成。该脚本读取 HMM 状态解码结果，优先使用包含 NDVI 的 `data/processed/curlew_states_decoded_env.csv`；若该文件不存在，则使用 `data/processed/curlew_states_decoded.csv`。在行为状态中，脚本优先选取“高速飞行”状态的步长作为飞行步长样本；若高速飞行样本不足，则退而使用“飞行”状态。为避免极小步长影响分布拟合，脚本仅保留大于 0.5 km 的飞行步长，并要求样本量不少于 30。

Lévy 步长分析使用 Python `powerlaw` 包拟合 power-law 分布，估计参数包括幂律指数 alpha 和最小拟合阈值 xmin。随后，脚本将 power-law 分布分别与 lognormal 和 exponential 分布进行似然比较，输出比较统计量和 p 值。结果保存为 `data/processed/curlew_levy_result.csv`。

本研究将该模块定位为飞行步长重尾特征的辅助分析。若 power-law 分布不优于 lognormal 或 exponential 等替代分布，则不能将结果解释为严格支持 Lévy flight。本项目结果显示高速飞行步长存在重尾特征，但分布比较不支持纯幂律模型优于替代模型，因此正文中仅将其表述为 Lévy-like 或重尾运动特征，而不作为主要机制结论。

## 2.6 停歇地识别与环境变量提取

停歇地识别同样由 `py/09_levy_stopovers.py` 完成，并建立在 HMM 行为状态解码结果之上。脚本首先筛选状态标签为“停歇”和“局部活动/觅食”的轨迹点，将其视为潜在停歇、觅食或局部活动位置。随后使用 DBSCAN 对这些点进行空间聚类，距离度量采用 haversine 距离。聚类参数来自 `config/project_config.json`：空间半径 `eps_km = 10` km，最小点数 `min_samples = 3`。脚本还将同一个体在同一空间聚类内的连续访问划分为事件，默认允许的最大时间间隔为 12 小时，并保留持续时间在配置范围内的访问事件。

该步骤输出三个文件：`data/processed/curlew_stopover_events.csv` 记录连续停歇事件，`data/processed/curlew_stopover_sites.csv` 记录空间聚类地点，`data/processed/curlew_stopovers.csv` 为兼容后续流程保留的停歇地事件表。每个停歇事件包含个体编号、中心经纬度、到达和离开时间、停留时长、点数、平均 NDVI、到达 NDVI 和风支持等字段。根据项目结果，共识别出 33 个停歇地或关键活动地候选。

由于空间聚类可能合并跨年度或跨季节重复访问，同一聚类并不一定代表单次迁徙停歇事件。为降低环境变量缺失和状态表版本差异带来的影响，`R/09b_rebuild_stopovers_env.R` 进一步根据状态解码表在每个停歇事件的到达与离开时间范围内回填环境变量，包括平均 NDVI、到达 NDVI、平均风支持和对应状态点数。该步骤输出 `data/processed/curlew_stopover_events_env.csv` 及相关质控结果。正文中将这些结果表述为“停歇地或关键活动热点候选”，并在涉及停留时长机制模型时使用更严格的时长子集。

## 2.7 最优停止/停歇时长模型

最优停止相关分析由 `R/10b_stopover_sensitivity.R` 和 `R/10_optimal_stopping.R` 实现。该模块用于探索到达时资源质量和风支持是否能够解释停歇地停留时长。由于样本量较小、资源变量为 NDVI 代理指标，且部分空间聚类具有极长持续时间，本文将该模块定义为探索性停歇时长模型，而不是对最优停止理论的严格机制检验。

`R/10b_stopover_sensitivity.R` 首先读取 `data/processed/curlew_stopover_events_env.csv`；若该文件不存在，则读取 `data/processed/curlew_stopovers.csv`。脚本对停留时长进行描述统计，输出 `output/tables/10b_stopover_duration_summary.csv` 和按时长排序的停歇地表 `output/tables/10b_stopovers_ordered_by_duration.csv`，并绘制停留时长直方图、log 停留时长直方图和箱线图。随后，脚本在三个数据子集上拟合敏感性模型：全部持续时间不少于 2 小时的停歇地、排除极长停留后的 2-240 小时子集，以及更严格的 2-168 小时子集。模型形式为 `log(duration_hr) ~ ndvi_arrive_z + wind_support_z`，其中 `ndvi_arrive_z` 和 `wind_support_z` 分别为到达 NDVI 和风支持的标准化值。敏感性分析结果输出为 `output/tables/10b_stopover_sensitivity_summary.csv` 和 `output/tables/10b_stopover_sensitivity_coefficients.csv`。

主停歇时长模型由 `R/10_optimal_stopping.R` 完成。该脚本对停歇地进行质控，要求停留时长有效、持续时间在 2-240 小时之间，并且到达 NDVI 和风支持不缺失。主模型同样采用线性模型 `log(duration_hr) ~ ndvi_arrive_z + wind_support_z`。模型系数输出至 `output/tables/10_optimal_stopping_lm_coefficients.csv`，预测结果输出至 `output/tables/10_optimal_stopping_predictions.csv`，模型参数和拟合指标输出至 `output/tables/10_optimal_stopping_params.csv`，预测值与观测值对比图输出至 `output/figures/10_optimal_stopping_pred_obs.png`。

为衔接后续情景模拟，脚本根据停歇时长模型结果生成 `lambda_proxy` 和 `Qstar_proxy` 两个代理参数。这里的代理参数仅用于构造探索性资源情景响应，不应解释为经过严格估计的最优停止阈值或行为决策参数。

## 2.8 NDVI 情景模拟

NDVI 情景模拟由 `R/11_climate_scenario_projection.R` 完成。该模块以停歇地环境表和 `output/tables/10_optimal_stopping_params.csv` 中的代理参数为输入，模拟不同 NDVI 变化情景下预测停留时长的变化。由于前一节停歇时长模型解释度较低且资源效应未得到显著支持，本节模拟被定义为探索性情景外推，而不是确定性气候变化预测。

脚本首先筛选持续时间大于 0 且不超过 240 小时、到达 NDVI 和风支持不缺失的停歇地。随后设定五种资源情景：当前 NDVI、NDVI 下降 5%、NDVI 下降 10%、NDVI 下降 20% 和 NDVI 上升 5%。对每个停歇地和每个情景，脚本按设定倍率调整到达 NDVI，并使用代理公式 `Delta t* = log(Q0 / Q*) / lambda` 计算预测停留时长，其中 `Q0` 为情景 NDVI，`Q*` 为 `Qstar_proxy`，`lambda` 为 `lambda_proxy`。当公式预测值小于 0 时，停留时长被截断为 0。

情景模拟还根据情景 NDVI 与 `Qstar_proxy` 的关系划分风险等级：低于阈值的地点被标记为高风险，接近阈值的地点被标记为中风险，其余为低风险。详细预测表输出为 `output/tables/11_climate_scenario_projection.csv`，情景汇总表输出为 `output/tables/11_climate_scenario_summary.csv`，情景图输出为 `output/figures/11_climate_scenario_projection.png`。

需要说明的是，项目中还包含 `py/11_climate_projection.py`，该脚本为 CMIP6/NetCDF 气候情景投影的骨架实现，但当前主结果链条使用的是 `R/11_climate_scenario_projection.R` 中基于 NDVI 扰动的探索性模拟。因此，本文方法与结果不将 Python 气候投影骨架作为已运行的正式分析结果。

## 2.9 SCVI 停歇地保育价值指数

SCVI（Stopover Conservation Value Index）由 `R/12_scvi_conservation_value.R` 构建，用于对 HMM 和 DBSCAN 识别出的停歇地或关键活动热点进行探索性保育价值排序。该指数整合空间使用强度、停留时长、资源质量和情景脆弱性四类信息，目的是形成候选保护地点清单，而非直接给出最终保护决策。

SCVI 的输入包括停歇地环境表和 NDVI 情景模拟结果。脚本优先读取 `data/processed/curlew_stopover_events_env.csv`，若不存在则读取 `data/processed/curlew_stopovers.csv`；情景模拟结果读取 `output/tables/11_climate_scenario_projection.csv`。在计算前，脚本保留中心经纬度、停留时长和到达 NDVI 有效，且停留时长大于 0 并不超过项目配置最大值的地点。

SCVI 包含四个标准化分项。第一，使用强度分项基于 `n_state_points` 或 `n_points`，经 `log1p` 转换后归一化至 0-1。第二，停留时长分项基于停歇地持续时间，并在主分析中将用于 SCVI 的时长上限设为 240 小时，以降低极长重复利用热点对排序的支配作用。第三，资源质量分项使用到达 NDVI；若到达 NDVI 不可用，则使用平均 NDVI。第四，气候/资源脆弱性分项来自 NDVI 下降 20% 情景下相对于当前情景的预测停留时长损失。

主分析权重设置为：使用强度 0.25、停留时长 0.30、资源质量 0.25、脆弱性 0.20。四个分项加权求和得到 SCVI。脚本还按 SCVI 分位数划分保育优先级：前 20% 为高优先级，50%-80% 为中优先级，其余为低优先级。SCVI 排序表输出至 `output/tables/12_scvi_stopover_ranking.csv`，项目汇总结果输出至 `output/tables/12_project_result_summary.csv`，排序条形图和空间分布图分别输出至 `output/figures/12_scvi_ranking_bar.png` 和 `output/figures/12_scvi_stopover_map.png`。

为评估指标对参数设置的敏感性，脚本还计算了不同情景下的排序稳定性，包括严格迁徙停歇 168 小时时长上限、平衡权重方案以及提高资源质量和脆弱性权重的方案。由于 SCVI 依赖权重设定、归一化方式、NDVI 代理变量和探索性情景模拟，本文将其解释为探索性综合保育指标，主要用于识别后续调查和管理评估的候选重点地点。
