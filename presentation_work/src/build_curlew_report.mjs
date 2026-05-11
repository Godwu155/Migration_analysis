import fs from "node:fs";
import path from "node:path";

const ARTIFACT_TOOL =
  "file:///C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const {
  Presentation,
  PresentationFile,
  row,
  column,
  grid,
  panel,
  text,
  image,
  rule,
  fill,
  hug,
  fixed,
  wrap,
  grow,
  fr,
  auto,
} = await import(ARTIFACT_TOOL);

const W = 1920;
const H = 1080;
const projectRoot = "D:/migration_project";
const workspace = path.join(projectRoot, "presentation_work");
const outputDir = path.join(workspace, "output");
const previewDir = path.join(workspace, "scratch", "previews");
fs.mkdirSync(outputDir, { recursive: true });
fs.mkdirSync(previewDir, { recursive: true });

const fig = (name) => path.join(projectRoot, "output", "figures", name).replaceAll("\\", "/");
const imgData = new Map();
function imageDataUrl(pathname) {
  const normalized = pathname.replaceAll("\\", "/");
  if (!imgData.has(normalized)) {
    const ext = path.extname(normalized).toLowerCase();
    const mime = ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : "image/png";
    const data = fs.readFileSync(normalized);
    imgData.set(normalized, `data:${mime};base64,${data.toString("base64")}`);
  }
  return imgData.get(normalized);
}

const C = {
  bg: "#F6F3EA",
  paper: "#FFFFFF",
  ink: "#102B26",
  muted: "#5C6E66",
  soft: "#E5E0D2",
  teal: "#0E7168",
  tealDark: "#073F3B",
  moss: "#647B48",
  clay: "#B85C38",
  amber: "#D59B2D",
  sky: "#4E91A8",
  red: "#A13E3A",
  gray: "#B8B1A4",
};

const font = "Microsoft YaHei";
const titleStyle = { fontFamily: font, fontSize: 54, bold: true, color: C.ink };
const subtitleStyle = { fontFamily: font, fontSize: 25, color: C.muted };
const bodyStyle = { fontFamily: font, fontSize: 25, color: C.ink };
const smallStyle = { fontFamily: font, fontSize: 17, color: C.muted };
const labelStyle = { fontFamily: font, fontSize: 18, bold: true, color: C.tealDark };

function T(value, opts = {}) {
  return text(value, {
    width: opts.width ?? fill,
    height: opts.height ?? hug,
    name: opts.name,
    style: { fontFamily: font, ...opts.style },
    columnSpan: opts.columnSpan,
    rowSpan: opts.rowSpan,
  });
}

function slideRoot(children, opts = {}) {
  return panel(
    { name: "slide-bg", width: fill, height: fill, fill: opts.fill ?? C.bg },
    column(
      {
        name: "slide-root",
        width: fill,
        height: fill,
        padding: opts.padding ?? { x: 86, y: 64 },
        gap: opts.gap ?? 28,
      },
      children,
    ),
  );
}

function titleBlock(title, subtitle, section = "") {
  return column({ name: "title-stack", width: fill, height: hug, gap: 12 }, [
    section
      ? T(section, {
          name: "section-label",
          width: wrap(760),
          style: { ...labelStyle, fontSize: 17, color: C.clay },
        })
      : T("", { name: "section-spacer", width: fixed(1), style: { fontSize: 1, color: C.bg } }),
    T(title, { name: "slide-title", style: titleStyle }),
    subtitle
      ? T(subtitle, { name: "slide-subtitle", width: wrap(1360), style: subtitleStyle })
      : T("", { name: "subtitle-spacer", width: fixed(1), style: { fontSize: 1, color: C.bg } }),
  ]);
}

function footer(slideNo, note = "欧亚杓鹬迁徙行为建模与停歇地保护价值评估") {
  return row({ name: "footer", width: fill, height: hug, align: "center", gap: 16 }, [
    rule({ name: "footer-rule", width: grow(1), stroke: C.soft, weight: 2 }),
    T(note, { name: "footer-note", width: wrap(880), style: { ...smallStyle, fontSize: 13 } }),
    T(String(slideNo).padStart(2, "0"), {
      name: "footer-page",
      width: fixed(42),
      style: { ...smallStyle, fontSize: 13, bold: true, color: C.teal },
    }),
  ]);
}

function figure(pathname, alt, name = "figure", fit = "contain") {
  return panel(
    {
      name: `${name}-frame`,
      width: fill,
      height: fill,
      fill: C.paper,
      padding: 20,
      borderRadius: 16,
    },
    image({ name, dataUrl: imageDataUrl(pathname), width: fill, height: fill, fit, alt }),
  );
}

function metric(value, label, color = C.teal) {
  return column({ name: `metric-${label}`, width: fill, height: hug, gap: 8 }, [
    T(value, { name: `metric-value-${label}`, style: { fontSize: 48, bold: true, color } }),
    T(label, { name: `metric-label-${label}`, style: { ...smallStyle, fontSize: 18, color: C.muted } }),
  ]);
}

function bulletList(items, name = "bullets", fs = 25) {
  return column(
    { name, width: fill, height: hug, gap: 16 },
    items.map((item, i) =>
      row({ name: `${name}-${i}`, width: fill, height: hug, gap: 14, align: "start" }, [
        T("—", {
          name: `${name}-dash-${i}`,
          width: fixed(28),
          style: { fontSize: fs, bold: true, color: C.clay },
        }),
        T(item, { name: `${name}-text-${i}`, style: { ...bodyStyle, fontSize: fs } }),
      ]),
    ),
  );
}

function statusLine(label, textValue, color) {
  return column({ name: `status-${label}`, width: fill, height: hug, gap: 10 }, [
    rule({ name: `status-rule-${label}`, width: fixed(160), stroke: color, weight: 7 }),
    T(label, { name: `status-label-${label}`, style: { fontSize: 27, bold: true, color: C.ink } }),
    T(textValue, { name: `status-text-${label}`, style: { fontSize: 22, color: C.muted } }),
  ]);
}

const presentation = Presentation.create({
  slideSize: { width: W, height: H },
});

function addSlide(root) {
  const slide = presentation.slides.add();
  slide.compose(root, { frame: { left: 0, top: 0, width: W, height: H }, baseUnit: 8 });
  return slide;
}

// 1. Cover
addSlide(
  panel(
    { name: "cover-bg", width: fill, height: fill, fill: C.tealDark },
    grid(
      {
        name: "cover-grid",
        width: fill,
        height: fill,
        columns: [fr(0.82), fr(1.18)],
        rows: [fr(1)],
        columnGap: 0,
      },
      [
        column(
          {
            name: "cover-copy",
            width: fill,
            height: fill,
            padding: { left: 92, right: 62, top: 86, bottom: 72 },
            gap: 30,
            justify: "center",
          },
          [
            T("项目报告", {
              name: "cover-kicker",
              width: wrap(480),
              style: { fontSize: 22, color: "#C7D9CB", bold: true },
            }),
            T("欧亚杓鹬迁徙行为建模与停歇地保护价值评估", {
              name: "cover-title",
              style: { fontSize: 62, bold: true, color: "#FFF9EA" },
            }),
            rule({ name: "cover-rule", width: fixed(260), stroke: C.amber, weight: 8 }),
            T("从 GPS 轨迹、气象与 NDVI 数据出发，识别行为状态、关键活动地，并构建探索性保护排序。", {
              name: "cover-subtitle",
              width: wrap(660),
              style: { fontSize: 26, color: "#DDEBE1" },
            }),
            T("Movebank + ERA5 + MODIS NDVI  ·  R / Python / Shiny", {
              name: "cover-foot",
              width: wrap(680),
              style: { fontSize: 18, color: "#B5CFC3" },
            }),
          ],
        ),
        image({
          name: "cover-track-map",
          dataUrl: imageDataUrl(fig("08_state_tracks.png")),
          width: fill,
          height: fill,
          fit: "cover",
          alt: "HMM state-colored curlew tracks",
        }),
      ],
    ),
  ),
);

// 2. Thesis
addSlide(
  slideRoot(
    [
      titleBlock(
        "这份报告回答三个问题",
        "把复杂轨迹分析压缩成一条可讲清楚的科学证据链。",
        "01 / 主线",
      ),
      grid(
        { name: "question-grid", width: fill, height: fill, columns: [fr(1), fr(1), fr(1)], columnGap: 54 },
        [
          statusLine("怎么移动？", "HMM 将连续轨迹拆解为停歇、局部活动、飞行与高速飞行四类状态。", C.teal),
          statusLine("停在哪里？", "基于低移动状态点的空间聚类，识别 33 个停歇地或关键活动热点。", C.clay),
          statusLine("哪里优先？", "综合使用强度、停留时长、资源质量与情景脆弱性，形成 SCVI 排序。", C.moss),
        ],
      ),
      footer(2),
    ],
    { gap: 34 },
  ),
);

// 3. Data foundation
addSlide(
  slideRoot(
    [
      titleBlock("数据基础：样本小，但时间跨度长", "当前分析以 5 只欧亚杓鹬的长期 GPS 轨迹为主轴。", "02 / 数据"),
      grid(
        { name: "data-grid", width: fill, height: fill, columns: [fr(1.05), fr(0.95)], columnGap: 70 },
        [
          column({ name: "data-metrics", width: fill, height: fill, gap: 38, justify: "center" }, [
            grid({ name: "metric-grid-a", width: fill, height: hug, columns: [fr(1), fr(1)], columnGap: 44, rowGap: 34 }, [
              metric("393,845", "原始轨迹记录", C.teal),
              metric("5", "追踪个体", C.clay),
              metric("2020-2025", "时间范围", C.moss),
              metric("69,278", "1 小时规则化点", C.sky),
            ]),
            T("数据链条同时匹配 ERA5 温度/风场与 MODIS NDVI，为行为状态和停歇地解释提供环境背景。", {
              name: "data-note",
              style: { fontSize: 26, color: C.ink },
            }),
          ]),
          column({ name: "data-caveats", width: fill, height: fill, gap: 20, justify: "center" }, [
            T("质量控制要点", { name: "qc-title", style: { fontSize: 34, bold: true, color: C.ink } }),
            bulletList(
              [
                "经纬度与时间字段完整，适合进入轨迹清洗和行为建模。",
                "NDVI 匹配总体可用，但不同个体的缺失与时间差异需要在解释时保留谨慎。",
                "后续涉及 NDVI 的模型与情景结果，应视为资源代理变量下的探索性证据。",
              ],
              "data-qc-list",
              24,
            ),
          ]),
        ],
      ),
      footer(3),
    ],
    { gap: 30 },
  ),
);

// 4. Workflow
const steps = [
  ["轨迹清洗", "去重、异常速度过滤、1 小时规则化"],
  ["环境匹配", "ERA5 温度/风场、MODIS NDVI"],
  ["行为识别", "2/3/4 状态 HMM，按 BIC 选模"],
  ["停歇地识别", "低移动状态点 + DBSCAN 聚类"],
  ["应用输出", "NDVI 情景模拟、SCVI 排序、Shiny 应用"],
];
addSlide(
  slideRoot(
    [
      titleBlock("分析流程是一条完整的可复现链条", "每一步都产生中间表、模型或图件，支撑下一步解释。", "03 / 方法"),
      column(
        { name: "workflow-stack", width: fill, height: fill, gap: 26, justify: "center" },
        steps.map((s, i) =>
          row({ name: `flow-row-${i}`, width: fill, height: hug, gap: 26, align: "center" }, [
            T(String(i + 1).padStart(2, "0"), {
              name: `flow-number-${i}`,
              width: fixed(74),
              style: { fontSize: 32, bold: true, color: [C.teal, C.moss, C.clay, C.sky, C.amber][i] },
            }),
            rule({ name: `flow-line-${i}`, width: fixed(110), stroke: [C.teal, C.moss, C.clay, C.sky, C.amber][i], weight: 5 }),
            T(s[0], { name: `flow-title-${i}`, width: fixed(330), style: { fontSize: 34, bold: true, color: C.ink } }),
            T(s[1], { name: `flow-text-${i}`, width: fill, style: { fontSize: 25, color: C.muted } }),
          ]),
        ),
      ),
      footer(4),
    ],
    { gap: 34 },
  ),
);

// 5. HMM model selection
addSlide(
  slideRoot(
    [
      titleBlock("HMM 结果支持四类行为状态", "4 状态模型 BIC 最低，且四类状态的步长梯度非常清晰。", "04 / 行为状态"),
      grid({ name: "hmm-grid", width: fill, height: fill, columns: [fr(0.85), fr(1.15)], columnGap: 62 }, [
        column({ name: "bic-proof", width: fill, height: fill, gap: 24, justify: "center" }, [
          T("BIC 比较", { name: "bic-title", style: { fontSize: 34, bold: true, color: C.ink } }),
          grid({ name: "bic-table", width: fill, height: hug, columns: [fr(0.6), fr(1)], rowGap: 18, columnGap: 28 }, [
            T("状态数", { name: "bic-h1", style: { ...labelStyle, color: C.muted } }),
            T("BIC", { name: "bic-h2", style: { ...labelStyle, color: C.muted } }),
            T("4", { name: "bic-4", style: { fontSize: 44, bold: true, color: C.teal } }),
            T("177,307.8", { name: "bic-4-v", style: { fontSize: 44, bold: true, color: C.teal } }),
            T("3", { name: "bic-3", style: { fontSize: 31, color: C.muted } }),
            T("182,804.7", { name: "bic-3-v", style: { fontSize: 31, color: C.muted } }),
            T("2", { name: "bic-2", style: { fontSize: 31, color: C.muted } }),
            T("193,207.5", { name: "bic-2-v", style: { fontSize: 31, color: C.muted } }),
          ]),
          T("BIC 差异足够大，说明数据更支持用四类行为状态描述轨迹。", {
            name: "bic-note",
            style: { fontSize: 24, color: C.muted },
          }),
        ]),
        column({ name: "state-table-stack", width: fill, height: fill, gap: 18, justify: "center" }, [
          T("状态解释按平均步长排序", { name: "state-table-title", style: { fontSize: 34, bold: true, color: C.ink } }),
          grid({ name: "state-table", width: fill, height: hug, columns: [fr(0.9), fr(0.95), fr(0.95), fr(1.55)], rowGap: 15, columnGap: 16 }, [
            T("状态", { name: "state-h1", style: labelStyle }),
            T("点数", { name: "state-h2", style: labelStyle }),
            T("均步长", { name: "state-h3", style: labelStyle }),
            T("解释", { name: "state-h4", style: labelStyle }),
            T("1", { name: "state-1", style: { fontSize: 25, bold: true, color: C.teal } }),
            T("15,907", { name: "state-1-n", style: { fontSize: 25, color: C.ink } }),
            T("0.022 km", { name: "state-1-step", style: { fontSize: 25, color: C.ink } }),
            T("停歇", { name: "state-1-label", style: { fontSize: 25, color: C.ink } }),
            T("2", { name: "state-2", style: { fontSize: 25, bold: true, color: C.moss } }),
            T("33,784", { name: "state-2-n", style: { fontSize: 25, color: C.ink } }),
            T("0.211 km", { name: "state-2-step", style: { fontSize: 25, color: C.ink } }),
            T("局部活动/觅食", { name: "state-2-label", style: { fontSize: 25, color: C.ink } }),
            T("3", { name: "state-3", style: { fontSize: 25, bold: true, color: C.clay } }),
            T("8,643", { name: "state-3-n", style: { fontSize: 25, color: C.ink } }),
            T("2.021 km", { name: "state-3-step", style: { fontSize: 25, color: C.ink } }),
            T("飞行", { name: "state-3-label", style: { fontSize: 25, color: C.ink } }),
            T("4", { name: "state-4", style: { fontSize: 25, bold: true, color: C.amber } }),
            T("405", { name: "state-4-n", style: { fontSize: 25, color: C.ink } }),
            T("46.928 km", { name: "state-4-step", style: { fontSize: 25, color: C.ink } }),
            T("高速飞行", { name: "state-4-label", style: { fontSize: 25, color: C.ink } }),
          ]),
        ]),
      ]),
      footer(5),
    ],
    { gap: 28 },
  ),
);

// 6. HMM tracks
addSlide(
  slideRoot(
    [
      titleBlock("状态着色轨迹揭示迁徙路线与活动热点", "图中颜色对应 HMM 解码后的行为状态，是后续停歇地识别的基础。", "04 / 行为状态"),
      figure(fig("08_state_tracks.png"), "State-colored tracks", "state-tracks"),
      footer(6),
    ],
    { padding: { x: 78, y: 48 }, gap: 22 },
  ),
);

// 7. Levy
addSlide(
  slideRoot(
    [
      titleBlock("飞行步长有重尾，但不能强称 Lévy flight", "分布比较提示：power-law 不是优于替代分布的解释。", "05 / 步长分布"),
      grid({ name: "levy-grid", width: fill, height: fill, columns: [fr(1), fr(1)], columnGap: 72 }, [
        column({ name: "levy-numbers", width: fill, height: fill, gap: 36, justify: "center" }, [
          metric("α = 2.38", "power-law 拟合参数", C.teal),
          metric("xmin = 1.30", "拟合阈值", C.moss),
          T("这些数值支持“步长分布存在长尾/异质性”这一描述。", {
            name: "levy-good",
            style: { fontSize: 28, color: C.ink },
          }),
        ]),
        column({ name: "levy-warning", width: fill, height: fill, gap: 26, justify: "center" }, [
          T("谨慎解释", { name: "levy-warning-title", style: { fontSize: 40, bold: true, color: C.clay } }),
          bulletList(
            [
              "相对 lognormal：R = -171.36，p ≈ 4.24e-35。",
              "相对 exponential：R = -80.33，p ≈ 0.005。",
              "负 R 值说明 power-law 在比较中并不占优。",
              "报告中应写作“重尾特征”，而不是“严格 Lévy flight”。",
            ],
            "levy-list",
            25,
          ),
        ]),
      ]),
      footer(7),
    ],
    { gap: 30 },
  ),
);

// 8. Stopovers
addSlide(
  slideRoot(
    [
      titleBlock("识别出 33 个停歇地或关键活动热点", "空间聚类结果可用于候选地筛选，但部分极长时长可能代表多年重复利用。", "06 / 停歇地"),
      grid({ name: "stop-grid", width: fill, height: fill, columns: [fr(0.9), fr(1.1)], columnGap: 58 }, [
        column({ name: "stop-metrics", width: fill, height: fill, gap: 32, justify: "center" }, [
          metric("33", "原始候选聚类", C.teal),
          metric("15 h", "停留时长中位数", C.moss),
          metric("45,186 h", "最大持续时长", C.clay),
          T("极长持续时长提醒我们：当前聚类更稳妥的表述是“关键活动热点”或“重复利用地点”。", {
            name: "stop-note",
            style: { fontSize: 25, color: C.muted },
          }),
        ]),
        grid({ name: "stop-figs", width: fill, height: fill, rows: [fr(1), fr(1)], columns: [fr(1)], rowGap: 22 }, [
          figure(fig("10b_log_duration_histogram.png"), "Log duration histogram", "log-duration"),
          figure(fig("10b_duration_boxplot.png"), "Duration boxplot", "duration-box"),
        ]),
      ]),
      footer(8),
    ],
    { gap: 26 },
  ),
);

// 9. Duration model
addSlide(
  slideRoot(
    [
      titleBlock("停留时长模型没有发现显著资源或风支持效应", "主模型解释度低，NDVI 与 wind support 只能作为探索性方向。", "07 / 停留时长模型"),
      grid({ name: "duration-model-grid", width: fill, height: fill, columns: [fr(1.18), fr(0.82)], columnGap: 48 }, [
        grid({ name: "duration-figs", width: fill, height: fill, columns: [fr(1), fr(1)], columnGap: 22 }, [
          figure(fig("10b_ndvi_vs_log_duration.png"), "NDVI versus log duration", "ndvi-scatter"),
          figure(fig("10b_wind_vs_log_duration.png"), "Wind support versus log duration", "wind-scatter"),
        ]),
        column({ name: "duration-read", width: fill, height: fill, gap: 28, justify: "center" }, [
          metric("n = 22", "2-240 小时建模子集", C.teal),
          metric("R² = 0.013", "主模型解释度", C.clay),
          T("NDVI：β = 0.038；wind support：β = 0.220，二者均不显著。", {
            name: "duration-coefs",
            style: { fontSize: 26, color: C.ink },
          }),
          T("结论应写成“当前数据未发现稳定效应”，而不是“资源无影响”。", {
            name: "duration-caution",
            style: { fontSize: 24, color: C.muted },
          }),
        ]),
      ]),
      footer(9),
    ],
    { padding: { x: 74, y: 52 }, gap: 22 },
  ),
);

// 10. Prediction vs observed
addSlide(
  slideRoot(
    [
      titleBlock("模型预测能力有限，适合做情景接口而非机制结论", "预测-观测关系进一步说明停留时长模型的解释力较弱。", "07 / 停留时长模型"),
      grid({ name: "pred-grid", width: fill, height: fill, columns: [fr(1.12), fr(0.88)], columnGap: 62 }, [
        figure(fig("10_optimal_stopping_pred_obs.png"), "Predicted versus observed duration", "pred-obs"),
        column({ name: "pred-text", width: fill, height: fill, gap: 28, justify: "center" }, [
          T("该模型的价值", { name: "pred-value-title", style: { fontSize: 38, bold: true, color: C.ink } }),
          bulletList(
            [
              "为后续 NDVI 扰动情景提供统一的计算接口。",
              "输出 lambda_proxy 与 Qstar_proxy 作为经验代理参数。",
              "不应被解释为严格验证的最优停歇行为阈值。",
            ],
            "pred-list",
            25,
          ),
        ]),
      ]),
      footer(10),
    ],
    { gap: 26 },
  ),
);

// 11. NDVI scenario
addSlide(
  slideRoot(
    [
      titleBlock("NDVI 下降情景会压低模型预测停留时长", "这是资源代理变量的敏感性演示，不是确定性气候预测。", "08 / 情景模拟"),
      grid({ name: "scenario-grid", width: fill, height: fill, columns: [fr(1.24), fr(0.76)], columnGap: 54 }, [
        figure(fig("11_climate_scenario_projection.png"), "NDVI scenario projection", "scenario-chart"),
        column({ name: "scenario-read", width: fill, height: fill, gap: 27, justify: "center" }, [
          metric("7.58 h", "当前 NDVI 平均预测停留", C.teal),
          metric("4.71 h", "NDVI 下降 10%", C.clay),
          metric("2.36 h", "NDVI 下降 20%", C.red),
          T("方向性信息有用，但依赖前一页的弱解释模型，所以只能作为保护假设生成工具。", {
            name: "scenario-caution",
            style: { fontSize: 24, color: C.muted },
          }),
        ]),
      ]),
      footer(11),
    ],
    { padding: { x: 74, y: 52 }, gap: 22 },
  ),
);

// 12. SCVI
addSlide(
  slideRoot(
    [
      titleBlock("SCVI 将多维证据合成为保护价值排序", "当前排序用于候选地筛选和后续监测设计，而非最终保护决策。", "09 / 保护排序"),
      grid({ name: "scvi-grid", width: fill, height: fill, columns: [fr(0.95), fr(1.05)], columnGap: 28 }, [
        figure(fig("12_scvi_ranking_bar.png"), "SCVI ranking bar chart", "scvi-bar"),
        figure(fig("12_scvi_stopover_map.png"), "SCVI stopover map", "scvi-map"),
      ]),
      footer(12),
    ],
    { padding: { x: 70, y: 48 }, gap: 20 },
  ),
);

// 13. Apps
addSlide(
  slideRoot(
    [
      titleBlock("项目已经从静态分析延伸到交互式应用", "Shiny 应用让用户在参数输入后查看状态概率、轨迹模拟和结果缓存。", "10 / 应用层"),
      grid({ name: "app-grid", width: fill, height: fill, columns: [fr(1), fr(1.05)], columnGap: 70 }, [
        column({ name: "app-modules", width: fill, height: fill, gap: 28, justify: "center" }, [
          statusLine("predictor_app", "输入当前位置、状态、温度、风支持、NDVI，模拟未来状态和轨迹。", C.teal),
          statusLine("viewer_app", "读取缓存结果，快速查看已有轨迹模拟输出。", C.moss),
          statusLine("results_app", "集中展示分析图表、表格与解释性结果。", C.clay),
        ]),
        column({ name: "app-outputs", width: fill, height: fill, gap: 24, justify: "center" }, [
          T("交互层输出", { name: "app-output-title", style: { fontSize: 40, bold: true, color: C.ink } }),
          bulletList(
            [
              "下一小时行为状态概率。",
              "多条模拟轨迹与终点分布。",
              "轨迹终点统计摘要。",
              "已有模型结果的低成本浏览入口。",
            ],
            "app-output-list",
            27,
          ),
          T("解释边界：这是情景模拟器，不是确定性预测器。", {
            name: "app-boundary",
            style: { fontSize: 25, bold: true, color: C.clay },
          }),
        ]),
      ]),
      footer(13),
    ],
    { gap: 30 },
  ),
);

// 14. Conclusion
addSlide(
  slideRoot(
    [
      titleBlock("结论：行为识别稳，保护排序需谨慎使用", "最有价值的产出是候选热点与可复现流程；资源效应和情景结果仍需验证。", "11 / 结论"),
      grid({ name: "conclusion-grid", width: fill, height: fill, columns: [fr(1), fr(1), fr(1)], columnGap: 50 }, [
        statusLine("强支持", "清洗后的轨迹可被 4 状态 HMM 稳定分解；状态步长梯度清晰。", C.teal),
        statusLine("部分支持", "33 个空间聚类可作为关键活动地候选；短时事件更接近迁徙停歇解释。", C.moss),
        statusLine("探索性", "Lévy、NDVI 情景和 SCVI 排序依赖模型假设，适合作为后续验证与监测设计的起点。", C.clay),
      ]),
      rule({ name: "closing-rule", width: fill, stroke: C.soft, weight: 2 }),
      T("下一步优先级：拆分连续停歇事件、完善 NDVI/风场匹配质控、扩大个体样本、检验 SCVI 权重稳健性。", {
        name: "next-steps",
        style: { fontSize: 28, bold: true, color: C.ink },
      }),
      footer(14, "报告生成日期：2026-05-10"),
    ],
    { gap: 34 },
  ),
);

const hydrationRequests = presentation.getPendingImageHydrationRequests();
if (hydrationRequests.length) {
  presentation.hydrateImageAssets(
    hydrationRequests.map((request) => {
      const uri = request.uri ?? "";
      if (uri.startsWith("data:")) {
        const match = uri.match(/^data:([^;,]+);base64,(.*)$/);
        if (!match) {
          throw new Error(`Unsupported image data URL for asset ${request.assetId}`);
        }
        return {
          assetId: request.assetId,
          contentType: match[1],
          data: Buffer.from(match[2], "base64"),
        };
      }
      const filePath = uri.replace(/^file:\/\//, "");
      const contentType = request.contentType ?? (filePath.toLowerCase().endsWith(".jpg") ? "image/jpeg" : "image/png");
      return {
        assetId: request.assetId,
        contentType,
        data: fs.readFileSync(filePath),
      };
    }),
  );
}

const pptx = await PresentationFile.exportPptx(presentation);
const pptxPath = path.join(outputDir, "curlew_migration_report.pptx");
await pptx.save(pptxPath);

for (const slide of presentation.slides.items) {
  const no = slide.index + 1;
  const png = await slide.export({ format: "png", width: W, height: H });
  fs.writeFileSync(
    path.join(previewDir, `slide_${String(no).padStart(2, "0")}.png`),
    Buffer.from(await png.arrayBuffer()),
  );
}

console.log(JSON.stringify({ pptxPath, previewDir, slides: presentation.slides.count }, null, 2));
