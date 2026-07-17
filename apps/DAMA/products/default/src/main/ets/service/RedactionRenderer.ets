/**
 * RedactionRenderer.ets — 用离屏画布把选中区域的打码效果、涂鸦与用户水印
 * 平摊进位图。预览与导出共用同一条渲染路径(所见即所得);
 * 导出重新编码为 JPEG,天然不携带原图元数据(EXIF/位置)。
 */

import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';
import { NRect, RedactionStyle, RiskRegion, Stroke } from '../model/Models';

export class RenderInput {
  regions: RiskRegion[] = [];
  strokes: Stroke[] = [];
  style: RedactionStyle = RedactionStyle.BLOCK;
  blockColor: string = '#000000';
  /** 空串 = 不加水印。 */
  watermarkText: string = '';
}

export class RedactionRenderer {
  /** 渲染并平摊。src 为 w×h 像素的源图,返回同尺寸新 PixelMap。 */
  static render(src: image.PixelMap, w: number, h: number, input: RenderInput): image.PixelMap {
    const canvas = new OffscreenCanvas(w, h, LengthMetricsUnit.PX);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(src, 0, 0, w, h);

    for (const r of input.regions) {
      if (!r.selected) {
        continue;
      }
      const rx = Math.max(0, Math.floor(r.box.x * w));
      const ry = Math.max(0, Math.floor(r.box.y * h));
      const rw = Math.min(w - rx, Math.ceil(r.box.w * w));
      const rh = Math.min(h - ry, Math.ceil(r.box.h * h));
      if (rw <= 0 || rh <= 0) {
        continue;
      }
      if (r.emoji.length > 0) {
        RedactionRenderer.drawEmoji(ctx, src, r.emoji, rx, ry, rw, rh);
      } else if (input.style === RedactionStyle.PIXELATE) {
        RedactionRenderer.pixelate(ctx, src, w, h, rx, ry, rw, rh, false);
      } else if (input.style === RedactionStyle.BLUR) {
        RedactionRenderer.pixelate(ctx, src, w, h, rx, ry, rw, rh, true);
      } else {
        ctx.fillStyle = input.blockColor;
        ctx.fillRect(rx, ry, rw, rh);
      }
    }

    for (const s of input.strokes) {
      RedactionRenderer.drawStroke(ctx, s, w, h);
    }

    if (input.watermarkText.length > 0) {
      RedactionRenderer.drawTiledWatermark(ctx, input.watermarkText, w, h);
    }

    return ctx.getPixelMap(0, 0, w, h);
  }

  /**
   * 马赛克 / 模糊 共用降采样再放大的手法:
   * smooth=false → 硬边像素块(马赛克);smooth=true → 软化(模糊,块状柔和)。
   */
  private static pixelate(ctx: OffscreenCanvasRenderingContext2D, src: image.PixelMap,
    w: number, h: number, rx: number, ry: number, rw: number, rh: number, smooth: boolean): void {
    const cell = smooth
      ? Math.max(3, Math.round(Math.min(w, h) * 0.008))
      : Math.max(6, Math.round(Math.min(w, h) * 0.015));
    const tw = Math.max(1, Math.round(rw / cell));
    const th = Math.max(1, Math.round(rh / cell));
    const tmp = new OffscreenCanvas(tw, th, LengthMetricsUnit.PX);
    const tctx = tmp.getContext('2d');
    tctx.imageSmoothingEnabled = true;
    tctx.drawImage(src, rx, ry, rw, rh, 0, 0, tw, th);
    const small = tctx.getPixelMap(0, 0, tw, th);
    ctx.imageSmoothingEnabled = smooth;
    ctx.drawImage(small, rx, ry, rw, rh);
    ctx.imageSmoothingEnabled = true;
  }

  /** 人脸表情覆盖:先把底下区域打上马赛克,再画表情(防止边角漏出)。 */
  private static drawEmoji(ctx: OffscreenCanvasRenderingContext2D, src: image.PixelMap,
    emoji: string, rx: number, ry: number, rw: number, rh: number): void {
    const size = Math.round(Math.min(rw, rh) * 1.1);
    ctx.save();
    ctx.font = size + 'px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(emoji, rx + rw / 2, ry + rh / 2);
    ctx.restore();
  }

  private static drawStroke(ctx: OffscreenCanvasRenderingContext2D, s: Stroke,
    w: number, h: number): void {
    if (s.points.length < 4) {
      return;
    }
    ctx.save();
    ctx.strokeStyle = s.color;
    ctx.lineWidth = Math.max(2, s.width * w);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(s.points[0] * w, s.points[1] * h);
    for (let i = 2; i < s.points.length; i += 2) {
      ctx.lineTo(s.points[i] * w, s.points[i + 1] * h);
    }
    ctx.stroke();
    ctx.restore();
  }

  /** 平铺斜排的用户水印(-30°,双层描印保证深浅底都可读)。 */
  private static drawTiledWatermark(ctx: OffscreenCanvasRenderingContext2D,
    text: string, w: number, h: number): void {
    const fs = Math.max(22, Math.round(Math.min(w, h) * 0.04));
    ctx.save();
    ctx.translate(w / 2, h / 2);
    ctx.rotate(-Math.PI / 6);
    ctx.font = fs + 'px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const metrics = ctx.measureText(text);
    const stepX = Math.max(1, metrics.width) + fs * 2.5;
    const stepY = fs * 4;
    const diag = Math.sqrt(w * w + h * h);
    let row = 0;
    for (let y = -diag / 2; y <= diag / 2; y += stepY) {
      const offset = (row % 2 === 0) ? 0 : stepX / 2;
      for (let x = -diag / 2 - offset; x <= diag / 2; x += stepX) {
        ctx.globalAlpha = 0.20;
        ctx.fillStyle = '#000000';
        ctx.fillText(text, x + fs * 0.05, y + fs * 0.05);
        ctx.globalAlpha = 0.38;
        ctx.fillStyle = '#FFFFFF';
        ctx.fillText(text, x, y);
      }
      row++;
    }
    ctx.restore();
  }

  /** 打包为 JPEG(重新编码 → 不带任何原图元数据)。 */
  static async encodeJpeg(map: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    const opts: image.PackingOption = { format: 'image/jpeg', quality: 92 };
    const buf = await packer.packing(map, opts);
    await packer.release();
    return buf;
  }
}
