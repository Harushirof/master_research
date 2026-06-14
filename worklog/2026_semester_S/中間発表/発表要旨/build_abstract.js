const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, AlignmentType } = require("docx");

const JP = "Yu Mincho";   // 明朝（要旨らしさ）。無ければWordが代替フォント
const title = "水晶振動発振器の位相同期制御による高純度信号作成";
const author = "福井晴士郎";
const advisor = "指導教員： 齋藤 晴雄";

const body = [
"精密な周波数基準信号源の改良は、通信・測位・計測といった現代の高度技術を支える根幹である。理想的には位相ノイズのない正弦波信号を得ることが究極の目標であり、この理想に近づくほど、コヒーレント光通信のチャネル容量、GNSS による測位精度、スペクトル解析の分解能、原子時計どうしの周波数比較精度など、広範な分野で性能向上が期待される。",
"現在、世界最高水準の周波数基準信号源としては、光格子時計（相対安定度 10⁻¹⁸ 級）、セシウム原子時計（SI 秒の定義）、水素メーザー（短期安定度）が実現されている。これらを統計合成して国際原子時（TAI）が生成されており、複数の独立な基準を平均化することで単一機の性能を上回るという考え方は時刻分野で確立している。実用面では、GPS 衛星信号を基準として民生用発振器を規律する GPS 規律発振器（GPSDO）、双方向衛星時刻周波数比較（TWSTFT）、各国標準研究所間を結ぶ光ファイバー周波数配信、古典的な位相同期回路（PLL）、注入同期（injection locking）といった多様な手法が確立している。一方、最高性能を持つ装置は大型・高価かつ外部基準への依存性を持ち、民生レベルで利用される恒温槽付水晶発振器（OCXO）は小型・安価で短期安定度に優れるものの、単体での位相安定度には物理的限界がある。",
"本研究はこのギャップに着目し、複数の OCXO を電気的に同期させて平均化することで、単体を上回る性能を持つ基準信号源を構築するアプローチを採る。これは、TAI が複数の原子時計を統計合成する発想を、より小規模・実時間で水晶発振器に適用する試みに相当する。複数信号のアンサンブル平均を意味のある形で取るためには、対象発振器の位相が時間的に揃っている必要があり、そのため本研究ではまず、複数 OCXO の位相を能動的に同期させるためのフィードバック制御セットアップの構築に取り組んだ。",
"具体的には、10 MHz の OCXO 2 台について、デジタルオシロスコープを用いて立ち上がりエッジ間時間差をリアルタイムに取得し、NI 製データ収集装置を介してアナログ制御電圧を一方の OCXO に印加することで、両者の位相差を任意の目標値に追従させる系を構築した。電圧パルス応答によるシステム同定からゲインを推定し、比例制御から状態空間フィードバック（位相誤差と周波数誤差の 2 状態系）まで段階的に発展させた結果、位相差を任意値で停止させる Phase 1 を達成した（10 回連続成功、標準偏差 0.4 ns 未満）。また、より高い分解能で位相情報を取得するため、両 OCXO 信号を 48 kHz のオーディオレコーダにステレオ録音して事後解析する方式も並行して進めている。",
"今後は、目標値追従を実現する Phase 2 の達成、複数発振器への同時制御の拡張、アンサンブル平均操作の実装、およびアラン分散を用いた位相安定度の定量評価を通じて、複数水晶発振器の同期と平均化が基準信号源の改良に寄与することを示すことを目指す。",
];

const children = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 120 },
    children: [new TextRun({ text: title, font: JP, bold: true, size: 30 })] }),
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 20 },
    children: [new TextRun({ text: author, font: JP, size: 24 })] }),
  new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { after: 260 },
    children: [new TextRun({ text: advisor, font: JP, size: 20 })] }),
  ...body.map(t => new Paragraph({
    alignment: AlignmentType.JUSTIFIED,
    spacing: { after: 140, line: 300 },
    indent: { firstLine: 220 },
    children: [new TextRun({ text: t, font: JP, size: 21 })] })),
];

const doc = new Document({
  styles: { default: { document: { run: { font: JP, size: 21 } } } },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 },
      margin: { top: 1418, right: 1418, bottom: 1418, left: 1418 } } },
    children }],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync("福井晴士郎_修論要旨.docx", buf); console.log("OK docx", buf.length); });
