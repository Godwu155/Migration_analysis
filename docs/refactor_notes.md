# 重构说明

## 你现有项目的主要问题

1. 同一职责有多个脚本版本：
   - `01_cleaning.R` 与 `cleaning.R`
   - `04_HMM_prepare.R` 与 `05_hmm_prepare_fixed.R`
2. 目录结构已经初步形成，但脚本之间还是“手工串联”，不是稳定的数据管线。
3. Python 脚本写死了 `D:/migration_project/...` 路径，无法移植。
4. HMM 前处理缺少统一的 burst 切分逻辑，导致你后来不得不再写一个 `fixed` 版本。
5. 输出文件放在 `data/clean/` 太多，模型对象和结果表没有进一步分层。

## 老脚本到新脚本的映射

- `00_check_raw.R` -> `R/02_check_raw.R`
- `01_cleaning.R` + `cleaning.R` -> `R/03_clean_tracking.R`
- `02_regularize.R` -> `R/04_regularize_tracks.R`
- `03_match_era5.py` -> `py/05_match_era5.py`
- `04_HMM_prepare.R` + `05_hmm_prepare_fixed.R` -> `R/06_prepare_hmm_data.R`
- `06_hmm_fit_base.R` + `07_hmm_compare_states.R` -> `R/07_fit_hmm_models.R` + `R/08_decode_hmm.R`

## 新结构的核心原则

- 每个脚本只做一步
- 每一步都有明确输入和输出
- 原始数据只读，不手改
- 同类输出分目录存放
- 配置集中管理

## 建议你接下来怎么做

1. 先把新脚本复制进正式项目
2. 先从 A/B 模块开始替换运行
3. 跑通后，再接 C/D/E
4. 以后只保留一个版本，不再保留“fixed / final / base / new2”这类文件名
