const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, AlignmentType } = require("docx");

const JP = "Yu Mincho";   // 明朝（要旨らしさ）。無ければWordが代替フォント

// 本文は 修論要旨_v3_260610.md（v3, 260610）を反映。
// md を更新したら、この sections も更新すること（v2/v3 のドリフト防止）。
const title = "複数水晶発振器の同期・平均化による高純度周波数信号源の実現";
const author = "福井晴士郎";
const advisor = "指導教員： 齋藤 晴雄";

const sections = [
  { h: "1. 背景と目的", body: [
    "精密な周波数基準信号源は、通信・測位・計測といった現代技術の基盤である。その理想は位相雑音のない正弦波であり、位相雑音が低いほどコヒーレント光通信のチャネル容量、GNSS測位精度、スペクトル分解能、原子時計どうしの比較精度などが向上する。本研究は、安価な水晶発振器を用いて、できる限り位相雑音の小さい基準信号源を構築することを目的とする。",
  ] },
  { h: "2. 現状と課題", body: [
    "市販の基準信号源は広い性能帯に分布する。各種発振器（TCXO・恒温槽付水晶発振器(OCXO)・ルビジウム(PRS10)・水素メーザー(iMaser)・高安定OCXO(cybershaft 等)）の位相雑音(dBc/Hz)を同一搬送波に換算して比較すると、高性能機ほど大型・高価かつ外部基準への依存を伴う。実用面ではGPS規律発振器(GPSDO)が長期基準として確立し、近傍オフセットで概ね −100 dBc/Hz 級に達する。一方、民生用OCXOは小型・安価で短期安定度に優れるが、単体の位相安定度には物理的限界がある。特に1秒より短い時間スケール（オフセット周波数 ≳1 Hz）の近傍位相雑音をどこまで下げられるかが鍵となる。",
  ] },
  { h: "3. アプローチ：複数源の平均化", body: [
    "単体の限界を超えるため、複数のOCXOを同期させて平均化する。互いに無相関な雑音は N 台の平均で電力が 1/N となり、2台で位相雑音が約3 dB（dBc/Hz）低下する。これは国際原子時(TAI)が多数の原子時計を統計合成する発想を、より小規模・実時間で水晶発振器に適用するものである。平均が意味を持つには各発振器の位相が時間的に揃っている必要があり、(a)雑音を注入せずに同期する制御と、(b)1秒未満の近傍位相雑音を測る高分解能測定の二つが前提となる。",
  ] },
  { h: "4. 手法と現状の結果", body: [
    "【測定法】2台の10 MHz OCXO信号をステレオ録音し、ヒルベルト変換で2台間の時間ジッタ差を抽出、位相雑音 L(f) [dBc/Hz] として評価する手法を構築した。これによりオフセット ≳0.1 Hz（=1秒未満の時間スケール）の近傍位相雑音をピコ秒級分解能で測定できる。",
    "【同期】デジタルオシロでエッジ間時間差(FRFR)を取得し、NI製DAQで一方のOCXOに制御電圧を印加する。最小電圧ステップ応答からプラントゲインを実測（K≈860 ns/(V·s)）し、この実測モデルに基づいて「必要な量だけ電圧を動かす」フィードバック則を考案した。",
    "【結果】従来の比例・微分(PID)制御は、制御電圧の過剰な動きによって短期位相雑音（ハンチング）を注入してしまう。これに対し、実測モデルに基づく制御は、追従ゲインを適切に選ぶと無制御(開ループ保持, HOLD)と同等の近傍位相雑音で同期できることを実測で確認した（モデルFBとHOLDの低周波位相雑音差 ≈ 0 dB）。すなわち「雑音を注入せずに同期する」段階に到達した。",
  ] },
  { h: "5. 今後の予定", body: [
    "同期した2台を平均（ミキサ等）して単体比 −3 dB の低減を実証し、N台へ拡張する。さらに、理論上 1/N 低減が成立する双方向（相互）結合へ制御を発展させ、アラン分散による長期安定度評価とあわせて、複数水晶発振器の同期・平均化が市販ベンチマーク（GPSDO等, −100 dBc/Hz級）に近づきうることを示す。",
  ] },
];

const children = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 120 },
    children: [new TextRun({ text: title, font: JP, bold: true, size: 30 })] }),
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 20 },
    children: [new TextRun({ text: author, font: JP, size: 24 })] }),
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 220 },
    children: [new TextRun({ text: advisor, font: JP, size: 20 })] }),
];

for (const sec of sections) {
  children.push(new Paragraph({
    spacing: { before: 80, after: 40 },
    children: [new TextRun({ text: sec.h, font: JP, bold: true, size: 21 })],
  }));
  for (const p of sec.body) {
    children.push(new Paragraph({
      alignment: AlignmentType.JUSTIFIED,
      spacing: { after: 100, line: 300 },
      indent: { firstLine: 220 },
      children: [new TextRun({ text: p, font: JP, size: 21 })],
    }));
  }
}

const doc = new Document({
  styles: { default: { document: { run: { font: JP, size: 21 } } } },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 },
      margin: { top: 1418, right: 1418, bottom: 1418, left: 1418 } } },
    children }],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync("福井晴士郎_修論要旨.docx", buf); console.log("OK docx", buf.length); });
