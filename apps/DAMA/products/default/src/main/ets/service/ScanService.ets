/**
 * ScanService.ets — 扫描管线:Core Vision 人脸检测 + OCR + 规则匹配 + 扫码。
 * 与 iOS 版 ScanService.swift 对应:
 *  - 各检测器独立 try/catch,一路失败不影响其余(扫描韧性)。
 *  - 标签行→值行的空间配对,恢复「标签与值分行」的姓名/CVV。
 *  - 全部离线,图片不出设备。
 */

import { textRecognition, faceDetector } from '@kit.CoreVisionKit';
import { scanCore, scanBarcode, detectBarcode } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NRect, OcrLine, OcrWord, RiskLevel, RiskRegion, RiskType } from '../model/Models';
import { TextRuleMatcher, RuleMatch } from './TextRuleMatcher';

const DOMAIN = 0x0001;
const TAG = 'ScanService';

export class ScanOutput {
  regions: RiskRegion[] = [];
  lines: OcrLine[] = [];
}

/** 由角点求归一化外接框(角点为像素坐标,左上原点)。 */
function rectFromCorners(points: textRecognition.PixelPoint[], imgW: number, imgH: number): NRect {
  let minX = Number.MAX_VALUE;
  let minY = Number.MAX_VALUE;
  let maxX = 0;
  let maxY = 0;
  for (const p of points) {
    minX = Math.min(minX, p.x);
    minY = Math.min(minY, p.y);
    maxX = Math.max(maxX, p.x);
    maxY = Math.max(maxY, p.y);
  }
  if (maxX <= minX || maxY <= minY) {
    return new NRect(0, 0, 0, 0);
  }
  return new NRect(minX / imgW, minY / imgH, (maxX - minX) / imgW, (maxY - minY) / imgH);
}

/** 词在行文本中的字符区间(顺序 indexOf,失败返回 -1)。 */
class WordSpan {
  start: number = -1;
  end: number = -1;
  rect: NRect = new NRect(0, 0, 0, 0);
}

export class ScanService {
  /**
   * 扫描一张图。px 为预览分辨率源图(imgW×imgH 像素)。
   * uri 非空时同时做条码识别(origW/origH 为原图尺寸,用于归一化)。
   */
  static async scan(px: image.PixelMap, imgW: number, imgH: number,
    uri: string, origW: number, origH: number): Promise<ScanOutput> {
    const out = new ScanOutput();

    // 1) OCR + 规则(独立失败)
    try {
      const visionInfo: textRecognition.VisionInfo = { pixelMap: px };
      const result = await textRecognition.recognizeText(visionInfo);
      out.lines = ScanService.collectLines(result, imgW, imgH);
      ScanService.applyRules(out);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'OCR failed: %{public}s', JSON.stringify(e));
    }

    // 2) 人脸(独立失败;表情覆盖)
    try {
      await faceDetector.init();
      const visionInfo: faceDetector.VisionInfo = { pixelMap: px };
      const faces = await faceDetector.detect(visionInfo);
      for (const f of faces) {
        if (f.probability < 0.35) {
          continue;
        }
        // 稍微外扩,让表情盖满整张脸。
        const padX = f.rect.width * 0.12;
        const padY = f.rect.height * 0.12;
        const box = new NRect(
          Math.max(0, (f.rect.left - padX) / imgW),
          Math.max(0, (f.rect.top - padY) / imgH),
          Math.min(1, (f.rect.width + padX * 2) / imgW),
          Math.min(1, (f.rect.height + padY * 2) / imgH));
        out.regions.push(new RiskRegion(RiskType.FACE, box, RiskLevel.HIGH, '人脸',
          f.probability, false, '😀'));
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'face detect failed: %{public}s', JSON.stringify(e));
    } finally {
      try {
        await faceDetector.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'face release failed');
      }
    }

    // 3) 二维码 / 条码(仅相册图,独立失败)
    if (uri.length > 0 && origW > 0 && origH > 0) {
      try {
        const options: scanBarcode.ScanOptions = {
          scanTypes: [scanCore.ScanType.ALL],
          enableMultiMode: true,
          enableAlbum: true
        };
        const inputImage: detectBarcode.InputImage = { uri: uri };
        const codes = await detectBarcode.decode(inputImage, options);
        for (const c of codes) {
          const r = c.scanCodeRect;
          if (r === undefined || r === null) {
            continue;
          }
          const box = new NRect(r.left / origW, r.top / origH,
            (r.right - r.left) / origW, (r.bottom - r.top) / origH);
          if (box.w <= 0 || box.h <= 0) {
            continue;
          }
          out.regions.push(new RiskRegion(RiskType.CODE, box, RiskLevel.HIGH, c.originalValue, 1));
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'barcode failed: %{public}s', JSON.stringify(e));
      }
    }

    ScanService.dedup(out);
    return out;
  }

  private static collectLines(result: textRecognition.TextRecognitionResult,
    imgW: number, imgH: number): OcrLine[] {
    const lines: OcrLine[] = [];
    for (const block of result.blocks) {
      for (const line of block.lines) {
        const rect = rectFromCorners(line.cornerPoints, imgW, imgH);
        if (rect.w <= 0 || rect.h <= 0 || line.value.length === 0) {
          continue;
        }
        const words: OcrWord[] = [];
        for (const w of line.words) {
          const wr = rectFromCorners(w.cornerPoints, imgW, imgH);
          if (wr.w > 0 && wr.h > 0 && w.value.length > 0) {
            words.push(new OcrWord(w.value, wr));
          }
        }
        lines.push(new OcrLine(line.value, rect, words));
      }
    }
    return lines;
  }

  private static applyRules(out: ScanOutput): void {
    const texts: string[] = [];
    for (const l of out.lines) {
      texts.push(l.text);
    }
    const sceneHint = TextRuleMatcher.containsContextKeywords(texts);

    for (const line of out.lines) {
      const matches = TextRuleMatcher.matches(line.text, sceneHint);
      for (const m of matches) {
        const box = m.wholeLine ? line.rect.clone() : ScanService.boxForRange(line, m.start, m.end);
        out.regions.push(new RiskRegion(m.type, box, m.level,
          line.text.substring(m.start, m.end), 1));
      }
    }

    // 标签行 → 值行 空间配对(姓名 / CVV 分行的表单布局)
    for (const label of out.lines) {
      if (TextRuleMatcher.isNameLabelLine(label.text)) {
        const value = ScanService.adjacentValue(label, out.lines, (t) => TextRuleMatcher.looksLikeName(t));
        if (value !== null && !ScanService.covered(out.regions, value.rect)) {
          out.regions.push(new RiskRegion(RiskType.NAME, value.rect.clone(), RiskLevel.MEDIUM, value.text, 1));
        }
      } else if (TextRuleMatcher.isCVVLabel(label.text)) {
        const value = ScanService.adjacentValue(label, out.lines, (t) => TextRuleMatcher.looksLikeCVV(t));
        if (value !== null && !ScanService.covered(out.regions, value.rect)) {
          out.regions.push(new RiskRegion(RiskType.PAYMENT, value.rect.clone(), RiskLevel.HIGH, value.text, 1));
        }
      }
    }
  }

  /** 匹配区间 → 归一化框:并集覆盖的词框;没有词框时按比例切分行框。 */
  private static boxForRange(line: OcrLine, start: number, end: number): NRect {
    const spans: WordSpan[] = [];
    let cursor = 0;
    for (const w of line.words) {
      const s = new WordSpan();
      const idx = line.text.indexOf(w.text, cursor);
      if (idx >= 0) {
        s.start = idx;
        s.end = idx + w.text.length;
        cursor = s.end;
      }
      s.rect = w.rect;
      spans.push(s);
    }
    let union: NRect | null = null;
    for (const s of spans) {
      if (s.start < 0) {
        continue;
      }
      if (s.start < end && s.end > start) {
        union = union === null ? s.rect.clone() : NRect.union(union, s.rect);
      }
    }
    if (union !== null) {
      return union;
    }
    // 兜底:按字符比例切分整行框。
    const len = Math.max(1, line.text.length);
    return new NRect(line.rect.x + line.rect.w * (start / len), line.rect.y,
      line.rect.w * ((end - start) / len), line.rect.h);
  }

  /** 找与标签行同行偏右、或紧邻下方,且内容满足 predicate 的值行。 */
  private static adjacentValue(label: OcrLine, lines: OcrLine[],
    predicate: (t: string) => boolean): OcrLine | null {
    let best: OcrLine | null = null;
    let bestDist = Number.MAX_VALUE;
    for (const cand of lines) {
      if (cand === label || !predicate(cand.text)) {
        continue;
      }
      const a = label.rect;
      const b = cand.rect;
      const vOverlap = Math.min(a.maxY, b.maxY) - Math.max(a.y, b.y);
      const sameRowRight = vOverlap > Math.min(a.h, b.h) * 0.5 &&
        b.x >= a.maxX - 0.01 && (b.x - a.maxX) < 0.35;
      const below = (b.y - a.maxY) > -0.005 && (b.y - a.maxY) < a.h * 2.0 &&
        Math.abs(a.midX - b.midX) < 0.3;
      if (!sameRowRight && !below) {
        continue;
      }
      const dist = Math.abs(b.midX - a.midX) + Math.abs(b.midY - a.midY);
      if (dist < bestDist) {
        bestDist = dist;
        best = cand;
      }
    }
    return best;
  }

  private static covered(regions: RiskRegion[], rect: NRect): boolean {
    for (const r of regions) {
      if (NRect.iou(r.box, rect) > 0.5) {
        return true;
      }
    }
    return false;
  }

  /** 同类型 IoU>0.6 去重,保留先加入者。 */
  private static dedup(out: ScanOutput): void {
    const kept: RiskRegion[] = [];
    for (const r of out.regions) {
      let dup = false;
      for (const k of kept) {
        if (k.type === r.type && NRect.iou(k.box, r.box) > 0.6) {
          dup = true;
          break;
        }
      }
      if (!dup) {
        kept.push(r);
      }
    }
    out.regions = kept;
  }
}
