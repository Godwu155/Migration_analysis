const path = require("node:path");
const fs = require("node:fs");
const pptxgen = require("C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pptxgenjs/dist/pptxgen.cjs.js");
const sizeOf = require("C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/image-size");

const pptx = new pptxgen();
pptx.layout = "LAYOUT_WIDE";
pptx.author = "Codex";
pptx.subject = "欧亚杓鹬迁徙行为建模与停歇地保护价值评估";
pptx.title = "欧亚杓鹬迁徙行为建模与停歇地保护价值评估";
pptx.company = "D:/migration_project";
pptx.lang = "zh-CN";
pptx.theme = {
  headFontFace: "Microsoft YaHei",
  bodyFontFace: "Microsoft YaHei",
  lang: "zh-CN",
};
pptx.defineLayout({ name: "CUSTOM_WIDE", width: 13.333, height: 7.5 });
pptx.layout = "CUSTOM_WIDE";

const PROJECT = "D:/migration_project";
const OUT = path.join(PROJECT, "presentation_work/output/curlew_migration_report.pptx");
const FIG = (name) => path.join(PROJECT, "output/figures", name);

const C = {
  bg: "F6F3EA",
  paper: "FFFFFF",
  ink: "102B26",
  muted: "5C6E66",
  soft: "DCD6C6",
  teal: "0E7168",
  tealDark: "073F3B",
  moss: "647B48",
  clay: "B85C38",
  amber: "D59B2D",
  sky: "4E91A8",
  red: "A13E3A",
};
const font = "Microsoft YaHei";
const SW = 13.333;
const SH = 7.5;

function addBg(slide, color = C.bg) {
  slide.background = { color };
}

function addText(slide, value, x, y, w, h, opts = {}) {
  slide.addText(value, {
    x, y, w, h,
    margin: 0,
    fontFace: font,
    fontSize: opts.fontSize ?? 16,
    bold: opts.bold ?? false,
    color: opts.color ?? C.ink,
    breakLine: false,
    fit: "shrink",
    valign: opts.valign ?? "top",
    align: opts.align ?? "left",
    paraSpaceAfterPt: 0,
    ...opts,
  });
}

function addLine(slide, x, y, w, color = C.soft, weight = 1.2) {
  slide.addShape(pptx.ShapeType.line, { x, y, w, h: 0, line: { color, width: weight } });
}

function title(slide, section, heading, sub) {
  addText(slide, section, 0.62, 0.48, 2.5, 0.36, { fontSize: 10, bold: true, color: C.clay });
  addText(slide, heading, 0.62, 0.95, 11.6, 0.58, { fontSize: 31, bold: true, color: C.ink });
  addText(slide, sub, 0.62, 1.58, 9.5, 0.48, { fontSize: 16, color: C.muted });
}

function footer(slide, no, note = "欧亚杓鹬迁徙行为建模与停歇地保护价值评估") {
  addLine(slide, 0.62, 7.05, 10.15, C.soft, 1);
  addText(slide, note, 10.9, 6.96, 1.9, 0.18, { fontSize: 7.5, color: C.muted, align: "right" });
  addText(slide, String(no).padStart(2, "0"), 12.9, 6.96, 0.25, 0.18, { fontSize: 7.5, color: C.teal, bold: true });
}

function metric(slide, value, label, x, y, w, color = C.teal) {
  addText(slide, value, x, y, w, 0.38, { fontSize: 24, bold: true, color });
  addText(slide, label, x, y + 0.42, w, 0.32, { fontSize: 11, color: C.muted });
}

function bullets(slide, items, x, y, w, fs = 15, color = C.ink, gap = 0.43) {
  items.forEach((item, i) => {
    addText(slide, "—", x, y + i * gap, 0.18, 0.25, { fontSize: fs, bold: true, color: C.clay });
    addText(slide, item, x + 0.28, y + i * gap, w - 0.28, 0.36, { fontSize: fs, color });
  });
}

function sectionLine(slide, label, body, x, y, w, color) {
  addLine(slide, x, y, 1.15, color, 3);
  addText(slide, label, x, y + 0.18, w, 0.32, { fontSize: 17, bold: true });
  addText(slide, body, x, y + 0.58, w, 0.72, { fontSize: 13.5, color: C.muted });
}

function imageContain(slide, imagePath, x, y, w, h) {
  const dim = sizeOf.imageSize(imagePath);
  const ar = dim.width / dim.height;
  let iw = w;
  let ih = w / ar;
  if (ih > h) {
    ih = h;
    iw = h * ar;
  }
  slide.addImage({ path: imagePath, x: x + (w - iw) / 2, y: y + (h - ih) / 2, w: iw, h: ih });
}

function figure(slide, imagePath, x, y, w, h) {
  slide.addShape(pptx.ShapeType.roundRect, {
    x, y, w, h,
    rectRadius: 0.08,
    fill: { color: C.paper },
    line: { color: C.paper, transparency: 100 },
  });
  imageContain(slide, imagePath, x + 0.12, y + 0.12, w - 0.24, h - 0.24);
}

function newSlide() {
  const slide = pptx.addSlide();
  addBg(slide);
  return slide;
}

// 1
{
  const slide = pptx.addSlide();
  addBg(slide, C.tealDark);
  slide.addShape(pptx.ShapeType.rect, { x: 0, y: 0, w: 5.1, h: SH, fill: { color: C.tealDark }, line: { transparency: 100 } });
  imageContain(slide, FIG("08_state_tracks.png"), 5.1, 0, 8.23, 7.5);
  addText(slide, "项目报告", 0.65, 1.28, 2.2, 0.25, { fontSize: 11, color: "C7D9CB", bold: true });
  addText(slide, "欧亚杓鹬迁徙行为建模\n与停歇地保护价值评估", 0.65, 2.05, 4.05, 1.2, { fontSize: 25, bold: true, color: "FFF9EA" });
  addLine(slide, 0.65, 3.48, 1.82, C.amber, 4);
  addText(slide, "从 GPS 轨迹、气象与 NDVI 数据出发，识别行为状态、关键活动地，并构建探索性保护排序。", 0.65, 3.75, 4.0, 0.65, { fontSize: 13.5, color: "DDEBE1" });
  addText(slide, "Movebank + ERA5 + MODIS NDVI  ·  R / Python / Shiny", 0.65, 4.68, 4.0, 0.25, { fontSize: 9.5, color: "B5CFC3" });
}

// 2
{
  const slide = newSlide();
  title(slide, "01 / 主线", "这份报告回答三个问题", "把复杂轨迹分析压缩成一条可讲清楚的科学证据链。");
  sectionLine(slide, "怎么移动？", "HMM 将连续轨迹拆解为停歇、局部活动、飞行与高速飞行四类状态。", 0.95, 3.0, 3.2, C.teal);
  sectionLine(slide, "停在哪里？", "基于低移动状态点的空间聚类，识别 33 个停歇地或关键活动热点。", 5.05, 3.0, 3.2, C.clay);
  sectionLine(slide, "哪里优先？", "综合使用强度、停留时长、资源质量与情景脆弱性，形成 SCVI 排序。", 9.05, 3.0, 3.2, C.moss);
  footer(slide, 2);
}

// 3
{
  const slide = newSlide();
  title(slide, "02 / 数据", "数据基础：样本小，但时间跨度长", "当前分析以 5 只欧亚杓鹬的长期 GPS 轨迹为主轴。");
  metric(slide, "393,845", "原始轨迹记录", 1.0, 2.9, 2.0, C.teal);
  metric(slide, "5", "追踪个体", 4.0, 2.9, 2.0, C.clay);
  metric(slide, "2020-2025", "时间范围", 1.0, 4.05, 2.0, C.moss);
  metric(slide, "69,278", "1 小时规则化点", 4.0, 4.05, 2.0, C.sky);
  addText(slide, "数据链条同时匹配 ERA5 温度/风场与 MODIS NDVI，为行为状态和停歇地解释提供环境背景。", 1.0, 5.25, 5.2, 0.48, { fontSize: 13.5 });
  addText(slide, "质量控制要点", 7.0, 3.0, 3.2, 0.32, { fontSize: 18, bold: true });
  bullets(slide, [
    "经纬度与时间字段完整，适合进入轨迹清洗和行为建模。",
    "NDVI 匹配总体可用，但不同个体的缺失与时间差异需要保留谨慎。",
    "涉及 NDVI 的模型与情景结果，应视为资源代理变量下的探索性证据。",
  ], 7.0, 3.55, 5.0, 13.5, C.ink, 0.62);
  footer(slide, 3);
}

// 4
{
  const slide = newSlide();
  title(slide, "03 / 方法", "分析流程是一条完整的可复现链条", "每一步都产生中间表、模型或图件，支撑下一步解释。");
  const steps = [
    ["01", "轨迹清洗", "去重、异常速度过滤、1 小时规则化", C.teal],
    ["02", "环境匹配", "ERA5 温度/风场、MODIS NDVI", C.moss],
    ["03", "行为识别", "2/3/4 状态 HMM，按 BIC 选模", C.clay],
    ["04", "停歇地识别", "低移动状态点 + DBSCAN 聚类", C.sky],
    ["05", "应用输出", "NDVI 情景模拟、SCVI 排序、Shiny 应用", C.amber],
  ];
  steps.forEach((s, i) => {
    const y = 2.4 + i * 0.78;
    addText(slide, s[0], 0.95, y, 0.42, 0.3, { fontSize: 14, bold: true, color: s[3] });
    addLine(slide, 1.55, y + 0.13, 0.9, s[3], 2.5);
    addText(slide, s[1], 2.8, y - 0.03, 2.1, 0.35, { fontSize: 18, bold: true });
    addText(slide, s[2], 5.3, y, 5.6, 0.3, { fontSize: 14, color: C.muted });
  });
  footer(slide, 4);
}

// 5
{
  const slide = newSlide();
  title(slide, "04 / 行为状态", "HMM 结果支持四类行为状态", "4 状态模型 BIC 最低，且四类状态的步长梯度非常清晰。");
  addText(slide, "BIC 比较", 0.9, 3.0, 2.0, 0.3, { fontSize: 17, bold: true });
  addText(slide, "状态数", 0.9, 3.45, 1.2, 0.2, { fontSize: 10, bold: true, color: C.muted });
  addText(slide, "BIC", 3.0, 3.45, 1.2, 0.2, { fontSize: 10, bold: true, color: C.muted });
  addText(slide, "4", 0.9, 3.85, 0.8, 0.35, { fontSize: 22, bold: true, color: C.teal });
  addText(slide, "177,307.8", 3.0, 3.85, 1.8, 0.35, { fontSize: 22, bold: true, color: C.teal });
  addText(slide, "3\n2", 0.9, 4.45, 0.8, 0.8, { fontSize: 15, color: C.muted, breakLine: false });
  addText(slide, "182,804.7\n193,207.5", 3.0, 4.45, 1.8, 0.8, { fontSize: 15, color: C.muted });
  addText(slide, "BIC 差异足够大，说明数据更支持用四类行为状态描述轨迹。", 0.9, 5.55, 4.5, 0.35, { fontSize: 12.5, color: C.muted });
  addText(slide, "状态解释按平均步长排序", 6.4, 3.1, 4.0, 0.3, { fontSize: 17, bold: true });
  const x = [6.4, 8.0, 9.65, 11.1];
  ["状态", "点数", "均步长", "解释"].forEach((h, i) => addText(slide, h, x[i], 3.55, 1.2, 0.2, { fontSize: 10.5, bold: true, color: C.tealDark }));
  const rows = [
    ["1", "15,907", "0.022 km", "停歇", C.teal],
    ["2", "33,784", "0.211 km", "局部活动/觅食", C.moss],
    ["3", "8,643", "2.021 km", "飞行", C.clay],
    ["4", "405", "46.928 km", "高速飞行", C.amber],
  ];
  rows.forEach((r, ri) => r.slice(0, 4).forEach((v, ci) => addText(slide, v, x[ci], 3.95 + ri * 0.42, ci === 3 ? 1.7 : 1.2, 0.25, { fontSize: 13.5, bold: ci === 0, color: ci === 0 ? r[4] : C.ink })));
  footer(slide, 5);
}

// 6
{
  const slide = newSlide();
  title(slide, "04 / 行为状态", "状态着色轨迹揭示迁徙路线与活动热点", "图中颜色对应 HMM 解码后的行为状态，是后续停歇地识别的基础。");
  figure(slide, FIG("08_state_tracks.png"), 3.55, 2.05, 6.2, 4.75);
  footer(slide, 6);
}

// 7
{
  const slide = newSlide();
  title(slide, "05 / 步长分布", "飞行步长有重尾，但不能强称 Lévy flight", "分布比较提示：power-law 不是优于替代分布的解释。");
  metric(slide, "α = 2.38", "power-law 拟合参数", 1.05, 3.3, 2.0, C.teal);
  metric(slide, "xmin = 1.30", "拟合阈值", 1.05, 4.45, 2.0, C.moss);
  addText(slide, "这些数值支持“步长分布存在长尾/异质性”这一描述。", 1.05, 5.55, 4.0, 0.35, { fontSize: 13.5 });
  addText(slide, "谨慎解释", 6.9, 3.2, 2.5, 0.35, { fontSize: 18, bold: true, color: C.clay });
  bullets(slide, [
    "相对 lognormal：R = -171.36，p ≈ 4.24e-35。",
    "相对 exponential：R = -80.33，p ≈ 0.005。",
    "负 R 值说明 power-law 在比较中并不占优。",
    "报告中应写作“重尾特征”，而不是“严格 Lévy flight”。",
  ], 6.9, 3.75, 5.2, 13, C.ink, 0.45);
  footer(slide, 7);
}

// 8
{
  const slide = newSlide();
  title(slide, "06 / 停歇地", "识别出 33 个停歇地或关键活动热点", "空间聚类结果可用于候选地筛选，但部分极长时长可能代表多年重复利用。");
  metric(slide, "33", "原始候选聚类", 1.0, 2.95, 2.1, C.teal);
  metric(slide, "15 h", "停留时长中位数", 1.0, 4.05, 2.1, C.moss);
  metric(slide, "45,186 h", "最大持续时长", 1.0, 5.15, 2.1, C.clay);
  addText(slide, "极长持续时长提醒我们：当前聚类更稳妥的表述是“关键活动热点”或“重复利用地点”。", 1.0, 6.05, 4.0, 0.4, { fontSize: 12.2, color: C.muted });
  figure(slide, FIG("10b_log_duration_histogram.png"), 7.3, 2.15, 4.8, 2.0);
  figure(slide, FIG("10b_duration_boxplot.png"), 7.3, 4.55, 4.8, 1.8);
  footer(slide, 8);
}

// 9
{
  const slide = newSlide();
  title(slide, "07 / 停留时长模型", "停留时长模型没有发现显著资源或风支持效应", "主模型解释度低，NDVI 与 wind support 只能作为探索性方向。");
  figure(slide, FIG("10b_ndvi_vs_log_duration.png"), 0.55, 2.1, 3.9, 4.75);
  figure(slide, FIG("10b_wind_vs_log_duration.png"), 4.65, 2.1, 3.9, 4.75);
  metric(slide, "n = 22", "2-240 小时建模子集", 9.1, 3.5, 2.0, C.teal);
  metric(slide, "R² = 0.013", "主模型解释度", 9.1, 4.65, 2.0, C.clay);
  addText(slide, "NDVI：β = 0.038；wind support：β = 0.220，二者均不显著。", 9.1, 5.6, 3.6, 0.33, { fontSize: 13.2 });
  addText(slide, "结论应写成“当前数据未发现稳定效应”，而不是“资源无影响”。", 9.1, 6.08, 3.6, 0.33, { fontSize: 12.2, color: C.muted });
  footer(slide, 9);
}

// 10
{
  const slide = newSlide();
  title(slide, "07 / 停留时长模型", "模型预测能力有限，适合做情景接口而非机制结论", "预测-观测关系进一步说明停留时长模型的解释力较弱。");
  figure(slide, FIG("10_optimal_stopping_pred_obs.png"), 0.95, 2.25, 6.0, 4.4);
  addText(slide, "该模型的价值", 7.8, 3.3, 2.4, 0.32, { fontSize: 18, bold: true });
  bullets(slide, [
    "为后续 NDVI 扰动情景提供统一的计算接口。",
    "输出 lambda_proxy 与 Qstar_proxy 作为经验代理参数。",
    "不应被解释为严格验证的最优停歇行为阈值。",
  ], 7.8, 3.85, 4.1, 13.5, C.ink, 0.58);
  footer(slide, 10);
}

// 11
{
  const slide = newSlide();
  title(slide, "08 / 情景模拟", "NDVI 下降情景会压低模型预测停留时长", "这是资源代理变量的敏感性演示，不是确定性气候预测。");
  figure(slide, FIG("11_climate_scenario_projection.png"), 0.95, 2.2, 7.5, 4.5);
  metric(slide, "7.58 h", "当前 NDVI 平均预测停留", 9.1, 3.0, 2.0, C.teal);
  metric(slide, "4.71 h", "NDVI 下降 10%", 9.1, 4.05, 2.0, C.clay);
  metric(slide, "2.36 h", "NDVI 下降 20%", 9.1, 5.1, 2.0, C.red);
  addText(slide, "方向性信息有用，但依赖前一页的弱解释模型，所以只能作为保护假设生成工具。", 9.1, 6.05, 3.45, 0.38, { fontSize: 12.2, color: C.muted });
  footer(slide, 11);
}

// 12
{
  const slide = newSlide();
  title(slide, "09 / 保护排序", "SCVI 将多维证据合成为保护价值排序", "当前排序用于候选地筛选和后续监测设计，而非最终保护决策。");
  figure(slide, FIG("12_scvi_ranking_bar.png"), 0.55, 2.05, 6.1, 4.8);
  figure(slide, FIG("12_scvi_stopover_map.png"), 6.85, 2.05, 5.9, 4.8);
  footer(slide, 12);
}

// 13
{
  const slide = newSlide();
  title(slide, "10 / 应用层", "项目已经从静态分析延伸到交互式应用", "Shiny 应用让用户在参数输入后查看状态概率、轨迹模拟和结果缓存。");
  sectionLine(slide, "predictor_app", "输入当前位置、状态、温度、风支持、NDVI，模拟未来状态和轨迹。", 0.95, 3.0, 4.2, C.teal);
  sectionLine(slide, "viewer_app", "读取缓存结果，快速查看已有轨迹模拟输出。", 0.95, 4.3, 4.2, C.moss);
  sectionLine(slide, "results_app", "集中展示分析图表、表格与解释性结果。", 0.95, 5.6, 4.2, C.clay);
  addText(slide, "交互层输出", 6.5, 3.0, 2.4, 0.32, { fontSize: 19, bold: true });
  bullets(slide, ["下一小时行为状态概率。", "多条模拟轨迹与终点分布。", "轨迹终点统计摘要。", "已有模型结果的低成本浏览入口。"], 6.5, 3.55, 4.8, 14.5, C.ink, 0.46);
  addText(slide, "解释边界：这是情景模拟器，不是确定性预测器。", 6.5, 5.7, 4.8, 0.35, { fontSize: 13.5, bold: true, color: C.clay });
  footer(slide, 13);
}

// 14
{
  const slide = newSlide();
  title(slide, "11 / 结论", "结论：行为识别稳，保护排序需谨慎使用", "最有价值的产出是候选热点与可复现流程；资源效应和情景结果仍需验证。");
  sectionLine(slide, "强支持", "清洗后的轨迹可被 4 状态 HMM 稳定分解；状态步长梯度清晰。", 0.9, 3.0, 3.2, C.teal);
  sectionLine(slide, "部分支持", "33 个空间聚类可作为关键活动地候选；短时事件更接近迁徙停歇解释。", 5.05, 3.0, 3.2, C.moss);
  sectionLine(slide, "探索性", "Lévy、NDVI 情景和 SCVI 排序依赖模型假设，适合作为后续验证与监测设计的起点。", 9.05, 3.0, 3.2, C.clay);
  addLine(slide, 0.9, 5.8, 11.3, C.soft, 1);
  addText(slide, "下一步优先级：拆分连续停歇事件、完善 NDVI/风场匹配质控、扩大个体样本、检验 SCVI 权重稳健性。", 0.9, 6.15, 11.0, 0.42, { fontSize: 15, bold: true });
  footer(slide, 14, "报告生成日期：2026-05-10");
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
pptx.writeFile({ fileName: OUT });
console.log(OUT);
