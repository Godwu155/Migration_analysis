# Multi-species Migration Framework

这是从欧亚杓鹬项目中拆出的通用候鸟迁徙分析框架。它放在独立目录中，不修改上一级已经完成的欧亚杓鹬项目。

第一版目标是“单物种可切换”：为每个候鸟物种准备一个 JSON 配置文件，然后运行同一套轨迹清洗、环境匹配、HMM 行为状态识别、停歇事件识别、停歇时长模型和 SCVI 排序流程。

## 目录结构

```text
multi_species_migration/
  config/
    default_parameters.json
    species/
      curlew.example.json
      goose.example.json
      raptor.example.json
  R/
  py/
  scripts/
  data/
    raw/
    climate/
  output/
    species_outputs/
```

生成结果会进入：

```text
output/species_outputs/{species_code}/
  data/clean/
  data/processed/
  tables/
  figures/
  models/
```

## 运行一个物种

从 `multi_species_migration/` 目录运行：

```bash
Rscript scripts/run_species.R config/species/curlew.example.json
```

也可以用环境变量指定配置：

```bash
SPECIES_CONFIG=config/species/curlew.example.json Rscript R/02_check_raw.R
```

Windows PowerShell 示例：

```powershell
$env:SPECIES_CONFIG = "config/species/curlew.example.json"
Rscript scripts/run_species.R config/species/curlew.example.json
```

如果 `python` 不在 PATH 中，可指定：

```powershell
$env:PYTHON_BIN = "py"
Rscript scripts/run_species.R config/species/curlew.example.json
```

## 新增一个物种

复制一个示例配置并去掉 `.example` 后缀：

```text
config/species/bar_tailed_godwit.json
```

至少修改这些字段：

- `project.species_code`
- `project.species_name`
- `project.common_name`
- `project.species_group`
- `input.raw_csv`
- `input.ndvi_csv`
- `input.climate_dir`

`species_group` 可先从这些模板中选择：

- `medium_wader`
- `large_waterbird`
- `raptor`
- `seabird`

模板参数在 `config/default_parameters.json` 中。它们只是起点，正式分析前需要根据目标物种的体型、飞行速度、采样间隔和栖息地使用方式重新校准。

## 重要说明

这个框架复用了原项目的科学流程，但不会把欧亚杓鹬的生态结论自动推广到其他物种。换物种后，尤其要重新检查：

- 最大速度阈值是否合理
- 1 小时规则化是否适合原始采样频率
- HMM 状态标签是否能被解释为停歇、局部活动或飞行
- DBSCAN 停歇半径和最大时间间隔是否合适
- NDVI 是否真能代表该物种的资源质量
- SCVI 权重是否符合该物种的保育问题

如果 NDVI 不适合目标物种，第一版仍可把它作为占位资源变量运行；后续应把 `environment.resource_proxy` 扩展为更合适的遥感或栖息地变量。
