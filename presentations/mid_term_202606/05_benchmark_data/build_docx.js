const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
        HeadingLevel, AlignmentType, LevelFormat, BorderStyle, WidthType,
        ShadingType, WidthType: WT } = require("docx");

const JP = "Yu Gothic";
const CW = 9026; // A4 content width (1" margins)
const border = { style: BorderStyle.SINGLE, size: 1, color: "BBBBBB" };
const borders = { top: border, bottom: border, left: border, right: border };
const HEADFILL = "D9E2F3";

function cell(text, w, opts = {}) {
  const runs = Array.isArray(text) ? text : [text];
  return new TableCell({
    borders,
    width: { size: w, type: WidthType.DXA },
    shading: opts.head ? { fill: HEADFILL, type: ShadingType.CLEAR } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({ children: runs.map(t => new TextRun({ text: String(t), bold: !!opts.head, font: JP, size: opts.size || 18 })) })],
  });
}
function mkTable(headers, rows, widths) {
  const headRow = new TableRow({ tableHeader: true, children: headers.map((h, i) => cell(h, widths[i], { head: true })) });
  const bodyRows = rows.map(r => new TableRow({ children: r.map((c, i) => cell(c, widths[i])) }));
  return new Table({ width: { size: CW, type: WidthType.DXA }, columnWidths: widths, rows: [headRow, ...bodyRows] });
}
function P(text, opts = {}) {
  return new Paragraph({ spacing: { after: 80 }, children: [new TextRun({ text, font: JP, size: opts.size || 20, italics: !!opts.i, bold: !!opts.b, color: opts.color })] });
}
function H(text, level) { return new Paragraph({ heading: level, spacing: { before: 200, after: 120 }, children: [new TextRun({ text, font: JP, bold: true })] }); }
function bullet(text) { return new Paragraph({ numbering: { reference: "b", level: 0 }, children: [new TextRun({ text, font: JP, size: 20 })] }); }
function code(text) { return new Paragraph({ spacing: { after: 40 }, shading: { fill: "F2F2F2", type: ShadingType.CLEAR }, children: [new TextRun({ text, font: "Consolas", size: 18 })] }); }

const t1w = [500, 1700, 1500, 1200, 700, 3426];
const t1 = [
  ["1","Ceyear2G","信号発生器","2 GHz","7","Ceyear 1435 series"],
  ["2","Ceyear3G","信号発生器","3 GHz","7","同上"],
  ["3","DST2","2.5GHz級信号源","2.5 GHz","6",""],
  ["4","DST1","信号源","3 GHz","6",""],
  ["5","SPXONo1","SPXO(簡易水晶)","20 MHz","865","E5052B実測(密データ)"],
  ["6","OEO","光電発振器(OEO)","10 GHz","7","超低位相雑音マイクロ波源"],
  ["7","Abracon-U","(Abracon)","100 MHz","6",""],
  ["8","EPSON-VCSO","VCSO","2.067 GHz","9",""],
  ["9","TCXO-CMOS","TCXO","27 MHz","775","実測(密), TG3225CEN系"],
  ["10","iMaser-10MLN","水素メーザー","10 MHz","6","iMaser3000 LN"],
  ["11","PRS10","ルビジウム","10 MHz","6","SRS PRS10"],
  ["12","DST-24.576","水晶系","24.576 MHz","6","DSTシリーズ"],
  ["13","cybershaft(638000円)","高安定OCXO","10 MHz","2","OP21A-D(1Hz<-121,10Hz<-140)"],
  ["14","cybershaft(121,000円)","高安定OCXO","10 MHz","1","OP13(1Hz<-113)"],
];

const t2w = [3000, 2000, 1300, 1400, 1326];
const t2 = [
  ["20230314_TG2016SKA_26MHz_..._data.xlsx","Epson TG2016SKA","26 MHz","SPXO/XO","実測xlsx"],
  ["20230314_TG3225CEN_27MHz_..._data.xlsx","Epson TG3225CEN","27 MHz","TCXO","実測xlsx"],
  ["E5052B測定データ_SG7050CAN_20MHz...xlsm","Epson SG7050CAN","20 MHz","SPXO","E5052B実測"],
  ["DST 22.579MHz.png / 24.576MHz.png","DST","22.579/24.576 MHz","水晶","図(png)"],
  ["PRS10 Rb.txt","SRS PRS10","10 MHz","Rb","txt数値"],
  ["iMaser3000.txt","T4Science iMaser3000","5/10/100 MHz","水素メーザー","txt数値(全grade)"],
  ["サイバーシャフト.txt","Cybershaft OP21A-D/OP13","10 MHz","高安定OCXO","txt数値"],
  ["Ceyear 1435 Series ... Datasheet.pdf","Ceyear 1435","—","信号発生器","データシート"],
];

const t3w = [2800, 2200, 1800, 2226];
const t3 = [
  ["Mutec REF10&MC-3+...pdf","Mutec REF10","10MHz基準","民生高級オーディオ用基準"],
  ["Mutec 21171.pdf","Mutec","クロック",""],
  ["RFX OS560-1005-020.pdf","RFX OS560","OCXO?",""],
  ["TamaDevice ...U7408LF-10MHz...pdf","TamaDevice U7408LF","10MHz OCXO",""],
  ["TamaDevice stp3091lf / stp3098lf.pdf","TamaDevice","OCXO",""],
];

const t35w = [2600, 1100, 4500, 826];
const g_ocxo = [
  ["Abracon AOCJY","10MHz","1:-90,10:-120,100:-135,1k:-145,10k:-150,100k:-150","high"],
  ["Micro Crystal Std OCXO","10MHz","10:-100,100:-130,1k:-140,10k:-145,100k:-145","med"],
  ["Morion MV89A","5MHz","1:-105,10:-130,100:-145,1k:-150,10k:-155","high"],
  ["Connor-Winfield OH320-LA","10MHz","1:-85,10:-115,100:-140,1k:-145,10k:-150,100k:-150","low"],
  ["IQD IQOV-116","10MHz","1k:-150 (公開はこの1点)","med"],
  ["Oscilloquartz 8607 Std (BVA)","10MHz","1:-118,10:-137,100:-143,1k:-145,10k:-145","high"],
  ["Oscilloquartz 8607 OptL","10MHz","1:-122,10:-137,100:-143,1k:-145,10k:-145","high"],
  ["Oscilloquartz 8788/8789 ULN","10MHz","1:-100,10:-130,100:-150,1k:-157,10k:-162,100k:-162","med"],
  ["Wenzel BTULN","10MHz","1:-120,10k:-178","med"],
  ["Cybershaft OP21A","10MHz","1:-121,10:-143","high"],
  ["Cybershaft OP13","10MHz","1:-113,10:-137","med"],
];
const g_rb = [
  ["SRS FS725 ($3995)","10MHz","10:-130,100:-140,1k:-150,10k:-155","high"],
  ["SRS PRS10 ($1895)","10MHz","10:-130,100:-140","high"],
  ["Microchip 8040C Std","10MHz","1:-72,10:-95,100:-130,1k:-140,10k:-148","high"],
  ["Microchip 8040C LN","10MHz","1:-100,10:-130,100:-144,1k:-150,10k:-150","high"],
  ["FEI FE-5680A","10MHz","10:-100,100:-125,1k:-145","high"],
  ["Datum LPRO-101","10MHz","1:-86,10:-96,100:-138,1k:-152,10k:-156,100k:-158","med"],
  ["Spectratime mRO-50","10MHz","1:-60,4:-70,10:-85,100:-110,1k:-135,10k:-140","high"],
];
const g_cs = [
  ["Microchip 5071A Cs","5MHz","1:-106,10:-136,100:-145,1k:-150,10k:-154,100k:-154","high"],
  ["Microchip 5071A Cs","10MHz","1:-100,10:-130,100:-145,1k:-150,10k:-154,100k:-154","high"],
  ["iMaser3000 Std","5MHz","1:-118,10:-135,100:-145,1k:-152,10k:-155,100k:-155","high"],
  ["iMaser3000 LN","5MHz","1:-130,10:-142,100:-152,1k:-156,10k:-156,100k:-156","high"],
  ["iMaser3000 Std","100MHz","1:-92,10:-105,100:-115,1k:-125,10k:-145,100k:-145","high"],
  ["Vremya-CH VCH-1003M Std","5MHz","1:-118,10:-135,100:-149,1k:-156,10k:-158,100k:-158","high"],
  ["Vremya-CH VCH-1003M OptL","5MHz","1:-130,10:-141,100:-151,1k:-156,10k:-159,100k:-159","high"],
  ["Vremya-CH VCH-1003M Std","100MHz","1:-92,10:-109,100:-122,1k:-122,10k:-152,100k:-152","high"],
  ["Microchip SA.45s CSAC","10MHz","1:-50,10:-70,100:-113,1k:-128,10k:-135,100k:-140","high"],
];
const g_gpsdo = [
  ["Leo Bodnar GPSDO","10MHz","1:-70,10:-100,100:-125,1k:-143,10k:-150,100k:-152","high"],
  ["Leo Bodnar Mini LBE-1420","10MHz","1:-70,10:-100,100:-125,1k:-145,10k:-150,100k:-153","high"],
  ["Trimble ThunderBolt","10MHz","10:-120,100:-135,1k:-135,10k:-145,100k:-145","high"],
  ["Jackson Labs HD CSAC GPSDO","10MHz","10:-75,100:-115,1k:-128,10k:-134,100k:-140","high"],
  ["Jackson Labs LN CSAC","10MHz","1:-100,10:-135,100:-145,1k:-150,10k:-155,100k:-155","med"],
  ["Brandywine GPSDO","10MHz","1:-90,10:-120,100:-145,1k:-151,10k:-153,100k:-155","high"],
  ["PTS GPS10eR Std","10MHz","1:-105,10:-135,100:-154,1k:-157,10k:-158,100k:-159","high"],
  ["PTS GPS10R/RB","10MHz","1:-96,10:-122,100:-138,1k:-148,10k:-150,100k:-150","high"],
];
const g_mems = [
  ["SiTime SiT5356 (MEMS)","10MHz","1:-80,10:-108,100:-127,1k:-148,10k:-154,100k:-154","high"],
  ["SiTime SiT5155 (MEMS)","10MHz","1:-80,10:-108,100:-127,1k:-148,10k:-154,100k:-154","high"],
  ["Epson TG2520SMN (TCXO)","26MHz","1:-66,10:-94,100:-120,1k:-142,10k:-157,100k:-161","high"],
  ["Abracon AST3TQ (TCXO)","10MHz","10:-95,100:-120,1k:-140,10k:-145,100k:-150","high"],
  ["NDK NT2016SA (TCXO)","26MHz","10:-83,100:-108,1k:-132,10k:-146,100k:-150","high"],
];
const PNHEAD = ["機種","搬送波","主要値 [Hz:dBc/Hz]","確度"];

const children = [
  new Paragraph({ spacing: { after: 160 }, children: [new TextRun({ text: "ベンチマーク位相雑音データ カタログ（260611）", font: JP, bold: true, size: 32 })] }),
  P("このフォルダで揃えている市販・公開の位相雑音(dBc/Hz)データの一覧。excelyomi.m は dBCperHz.xlsx の各シートを読み、figure1=そのまま / figure2=10MHz換算で重ね描きする（260611で20→10MHz化）。", { i: true }),
  P("換算式: L_10MHz = L_f + 20·log10(0.01[GHz] / f[GHz])（搬送波換算、kijun=0.01）。", { i: true }),

  H("1. dBCperHz.xlsx に入っている14機種（excelyomi が描画）", HeadingLevel.HEADING_1),
  P("各シート: A2=搬送波[GHz], A3=点数N, A4:B(3+N)=offset[Hz], L(f)[dBc/Hz]。"),
  mkTable(["#","シート名(凡例)","種別(推定)","搬送波","点数","備考"], t1, t1w),
  P("注: このデータ群は元々「2.5GHz信号源の比較」目的のため搬送波がバラバラ（2〜10GHz と 10〜100MHz が混在）。10MHz換算で同一軸に揃える。", { i: true }),

  H("既知の数値（テキスト生データより）", HeadingLevel.HEADING_2),
  P("PRS10 (Rb, 10MHz) [Hz→dBc/Hz]: 1→−102, 10→−135, 100→−148, 1k→−152, 10k→−152, 100k→−152"),
  P("iMaser-10MLN (水素メーザー, 10MHz, Standard/LN): 1→−112/−124, 10→−129/−136, 100→−139/−147, 1k→−146/−151, 10k→−149/−153, 100k→−149/−153"),
  P("cybershaft: OP21A-D 1Hz<−121, 10Hz<−140（ADEV τ=1s<1.6e-13） / OP13 1Hz<−113"),

  H("2. フォルダ内の生データ・データシート（xlsx未収録分）", HeadingLevel.HEADING_1),
  mkTable(["ファイル","機種","搬送波","種別","形式"], t2, t2w),
  H("市販品phase noise/（データシートPDF）", HeadingLevel.HEADING_2),
  mkTable(["ファイル","機種","種別","備考"], t3, t3w),

  H("3. データの偏り（追加で埋めるべき所）", HeadingLevel.HEADING_1),
  bullet("10MHz OCXO の市販高性能機（Wenzel, Morion MV89A 等）が手薄 → 自作の比較相手として重要。"),
  bullet("GPSDO（要旨のベンチマーク「−100 dBc/Hz級」の主役）が未収録。"),
  bullet("Cs一次標準（5071A 等）が未収録。"),
  bullet("低コスト帯（MEMS, 安価TCXO）の対比サンプルも薄い。"),
  P("→ 下記「3.5 追加データ」で収集・整備（Web調査43機種, 出典検証済み）。"),

  H("3.5 追加データ（260611 Web調査・出典検証済み 43機種）", HeadingLevel.HEADING_1),
  P("マルチエージェントで収集47→出典検証通過43機種。値は各データシートの搬送波でのSSB位相雑音[dBc/Hz]（一部は spec上限「<」値）。MATLAB: benchmark_extra_data.m、描画: overlay_benchmark_full_10MHz.m（10MHz換算・種別色＋本研究データ重ね）。例「1:-90」=1Hzで -90 dBc/Hz。", { i: true }),
  H("OCXO（恒温槽付水晶）", HeadingLevel.HEADING_2),
  mkTable(PNHEAD, g_ocxo, t35w),
  H("ルビジウム（Rb）", HeadingLevel.HEADING_2),
  mkTable(PNHEAD, g_rb, t35w),
  H("セシウム / 水素メーザー（一次標準級）", HeadingLevel.HEADING_2),
  mkTable(PNHEAD, g_cs, t35w),
  H("GPSDO / 規律発振器（要旨ベンチマークの主役）", HeadingLevel.HEADING_2),
  mkTable(PNHEAD, g_gpsdo, t35w),
  P("注: GPSDOの短期(近傍)は内部OCXO/Rb由来でGPS規律は長期。近傍 -100〜-120 dBc/Hz級が実力。", { i: true }),
  H("低コスト MEMS / TCXO（対比用・安価帯）", HeadingLevel.HEADING_2),
  mkTable(PNHEAD, g_mems, t35w),
  P("⚠️ 確度 low/med は PDF table reflow 等で要再確認（特に Connor-Winfield=low）。spec上限「<」値は実測より良い場合あり。", { i: true, color: "AA0000" }),

  H("4. 使い方（10MHz換算図）", HeadingLevel.HEADING_1),
  code("cd('...\\260611\\2024 0314 2.5GHz信号源重ね描き')"),
  code("excelyomi        % figure1=そのまま, figure2=10MHz換算(本命)"),
  code("% figure2 を保存 → ベンチマークマップ"),
  P("（追加データを取り込む拡張版プロッタ overlay_benchmark_10MHz.m を別途用意）", { i: true }),
];

const doc = new Document({
  styles: { default: { document: { run: { font: JP, size: 20 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 26, bold: true, font: JP }, paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 22, bold: true, font: JP }, paragraph: { spacing: { before: 160, after: 100 }, outlineLevel: 1 } },
    ] },
  numbering: { config: [ { reference: "b", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 600, hanging: 300 } } } }] } ] },
  sections: [{ properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } }, children }],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync("データ一覧_カタログ_260611.docx", buf); console.log("OK: データ一覧_カタログ_260611.docx", buf.length, "bytes"); });
