# -*- coding: utf-8 -*-
"""
slidekit — 齋藤研の卒論/中間発表フォーマットでスライドを作るヘルパー。

考え方（重要）:
  デザイン（濃紺アクセント・見出し・フォント・■箇条書き）は assets/template.pptx の
  スレイドマスター/レイアウト '1行タイトル+本文' に入っている。手作りで再現しようとすると
  必ずズレるので、**テンプレートを開き、そのレイアウトでスライドを足してプレースホルダを
  埋める** ことで本物の体裁をそのまま継承する。

使い方:
  from slidekit import Deck
  d = Deck()                                  # テンプレートを開く
  d.set_title(["水晶振動発振器の位相同期制御", "による高純度信号作成"],
              student="08-XXXXXX 福井 晴士郎", date="2026/06/24")
  d.set_index(["01 研究背景","02 本研究の目標","03 先行研究","04 研究方法",
               "05 実験と結果","06 考察と今後の展望","Appendix"])
  d.content("01 研究背景：…", ["■の本文1","■の本文2",(1,"●下位の本文")],
            images=["/abs/fig.png"], caps=["図の説明"], layout="right")
  d.content("04-5 制御ロジック", [...], images=[a,b], layout="below2")
  d.save("out.pptx")                          # 仕上げ（卒論の元コンテンツを削除して保存）

注意:
  - bullets は文字列（第1階層=■）か (level, 文字列) のタプル。level1=●, level2=→ は
    レイアウトの箇条書きスタイルに従う。
  - images は絶対パス推奨。layout は 'right'(右に1枚) / 'below2'(下に2枚) / 'below'(下に1枚大)。
  - 図がまだ無い箇所は placeholder=... で灰色の枠（「○○：作成予定」）を置ける。
"""
import os
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
from pptx.oxml.ns import qn
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.normpath(os.path.join(HERE, "..", "assets", "template.pptx"))
CONTENT_LAYOUT = "1行タイトル+本文"     # 本文スライドのレイアウト名（デザインの本体）
NAVY = RGBColor(0x00, 0x0F, 0x78)
GRAY = RGBColor(0x59, 0x59, 0x59)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
JP = "Yu Gothic"
SW = 10.833  # スライド幅[in]（卒論テンプレ＝9906000EMU）


def _ea(run, font=JP):
    """日本語フォントを latin/ea 両方に設定（python-pptx に get_or_add_ea が無いため手動）。"""
    run.font.name = font
    rPr = run._r.get_or_add_rPr()
    latin = rPr.get_or_add_latin(); latin.set("typeface", font)
    ea = rPr.find(qn("a:ea"))
    if ea is None:
        ea = rPr.makeelement(qn("a:ea"), {}); latin.addnext(ea)
    ea.set("typeface", font)


def _fit(path, maxw, maxh):
    iw, ih = Image.open(path).size; ar = iw / ih
    w = maxw; h = w / ar
    if h > maxh:
        h = maxh; w = h * ar
    return w, h


class Deck:
    def __init__(self, template=None):
        self.prs = Presentation(template or TEMPLATE)
        self._n0 = len(self.prs.slides._sldIdLst)   # 削除対象＝元の本文スライド数
        self._page = 1

    # ---------- 低レベル ----------
    def _layout(self, name=CONTENT_LAYOUT):
        for l in self.prs.slide_layouts:
            if l.name == name:
                return l
        return self.prs.slide_layouts[0]

    def _find_tb(self, slide, substr):
        for sh in slide.shapes:
            if sh.has_text_frame and substr in sh.text_frame.text:
                return sh
        return None

    def _set_tf(self, tf, lines):
        """テキストフレームの文字を入れ替え（元の1行目の書式＝サイズ/色/太字を継承）。"""
        size = bold = color = None
        for p in tf.paragraphs:
            for r in p.runs:
                size = r.font.size; bold = r.font.bold
                try:
                    if r.font.color and r.font.color.type is not None:
                        color = r.font.color.rgb
                except Exception:
                    pass
                break
            if size is not None:
                break
        tf.clear()
        for i, ln in enumerate(lines):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            r = p.add_run(); r.text = ln
            if size is not None:
                r.font.size = size
            if bold is not None:
                r.font.bold = bold
            if color is not None:
                r.font.color.rgb = color
            _ea(r)

    def _pic(self, slide, path, l, t, maxw, maxh):
        if not (path and os.path.isfile(path)):
            self._ph(slide, l, t, maxw, maxh, "[図ファイル無し: %s]" % os.path.basename(str(path)))
            return
        w, h = _fit(path, maxw, maxh)
        slide.shapes.add_picture(path, Inches(l + (maxw - w) / 2), Inches(t + (maxh - h) / 2), Inches(w), Inches(h))

    def _ph(self, slide, l, t, w, h, text):
        sp = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(l), Inches(t), Inches(w), Inches(h))
        sp.fill.solid(); sp.fill.fore_color.rgb = RGBColor(0xF2, 0xF2, 0xF2)
        sp.line.color.rgb = GRAY; sp.line.width = Pt(1); sp.shadow.inherit = False
        tf = sp.text_frame; tf.word_wrap = True; tf.vertical_anchor = MSO_ANCHOR.MIDDLE
        p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
        r = p.add_run(); r.text = text; r.font.size = Pt(12); r.font.color.rgb = GRAY; _ea(r)

    def _cap(self, slide, l, t, w, text):
        tb = slide.shapes.add_textbox(Inches(l), Inches(t), Inches(w), Inches(0.3))
        tf = tb.text_frame; tf.word_wrap = True
        p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
        r = p.add_run(); r.text = text; r.font.size = Pt(9); r.font.color.rgb = GRAY; _ea(r)

    # ---------- 表紙・Index ----------
    def set_title(self, title_lines, student=None, date=None, lab=None):
        """表紙（スライド0）の文字を差し替え。指定したものだけ変更。"""
        s = self.prs.slides[0]
        tb = self._find_tb(s, "位相ノイズ測定")            # 元タイトル
        if tb and title_lines:
            self._set_tf(tb.text_frame, title_lines if isinstance(title_lines, list) else [title_lines])
        if student:
            tb = self._find_tb(s, "福井") or self._find_tb(s, "08-")
            if tb:
                self._set_tf(tb.text_frame, [student])
        if date:
            tb = self._find_tb(s, "2025/02/05") or self._find_tb(s, "2025")
            if tb:
                self._set_tf(tb.text_frame, [date])
        if lab:
            tb = self._find_tb(s, "研究室")
            if tb:
                self._set_tf(tb.text_frame, [lab])

    def set_index(self, items):
        """Index（スライド1）のシェブロンを items で作り直す（濃紺・白文字）。"""
        s = self.prs.slides[1]
        for sh in list(s.shapes):
            if sh.shape_type == 6:   # GROUP（既存シェブロン）
                sh._element.getparent().remove(sh._element)
        n = len(items); h = 0.62; gap = 0.16
        total = n * h + (n - 1) * gap
        top = max(1.55, (7.5 - total) / 2 + 0.2)
        for i, it in enumerate(items):
            ch = s.shapes.add_shape(MSO_SHAPE.CHEVRON, Inches(1.3), Inches(top + i * (h + gap)), Inches(7.4), Inches(h))
            ch.fill.solid(); ch.fill.fore_color.rgb = NAVY; ch.line.fill.background(); ch.shadow.inherit = False
            tf = ch.text_frame; tf.vertical_anchor = MSO_ANCHOR.MIDDLE; tf.word_wrap = False
            p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
            r = p.add_run(); r.text = "　" + it; r.font.size = Pt(15); r.font.bold = True; r.font.color.rgb = WHITE; _ea(r)

    # ---------- 本文スライド ----------
    def content(self, title, bullets, images=None, caps=None, layout="right", placeholder=None):
        s = self.prs.slides.add_slide(self._layout())
        s.shapes.title.text = title                          # 見出し（濃紺アクセントはレイアウト由来）
        body = s.placeholders[1]; tf = body.text_frame; tf.word_wrap = True
        for i, b in enumerate(bullets):
            lvl, txt = b if isinstance(b, tuple) else (0, b)
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.level = lvl
            r = p.add_run(); r.text = txt; _ea(r)            # ■/●/→ はレイアウトの箇条書きに従う
        images = images or []; caps = caps or []
        if placeholder is not None:
            body.width = Inches(4.9)
            self._ph(s, 5.5, 2.0, 4.85, 3.7, placeholder)
        elif layout == "right" and images:
            body.width = Inches(4.85)
            self._pic(s, images[0], 5.5, 2.0, 4.9, 4.4)
            if caps:
                self._cap(s, 5.5, 6.5, 4.9, caps[0])
        elif layout == "below2" and images:
            body.height = Inches(1.9)
            cw = (SW - 1.0) / 2
            for i, im in enumerate(images[:2]):
                self._pic(s, im, 0.45 + i * (cw + 0.1), 3.7, cw, 2.7)
                if i < len(caps):
                    self._cap(s, 0.45 + i * (cw + 0.1), 6.55, cw, caps[i])
        elif images:                                          # below（1枚を下に大きく）
            body.height = Inches(2.3)
            self._pic(s, images[0], 1.5, 4.2, 7.8, 2.9)
            if caps:
                self._cap(s, 1.5, 7.2, 7.8, caps[0])
        return s

    def divider(self, title):
        """中表紙（章区切り）。レイアウト '中表紙' を使う。"""
        s = self.prs.slides.add_slide(self._layout("中表紙"))
        if s.shapes.title is not None:
            s.shapes.title.text = title
        return s

    # ---------- 仕上げ ----------
    def save(self, out_path):
        """元テンプレの本文スライド(2..)を削除してから保存。
        ※新スライドは末尾に足してあるので、削除後の並び＝表紙・Index・新本文。"""
        sldIdLst = self.prs.slides._sldIdLst
        ids = list(sldIdLst)
        for i in sorted(range(2, self._n0), reverse=True):
            rId = ids[i].get(qn("r:id"))
            self.prs.part.drop_rel(rId)
            sldIdLst.remove(ids[i])
        self.prs.save(out_path)
        return out_path
