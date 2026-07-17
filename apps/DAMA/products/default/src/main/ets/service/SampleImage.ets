/**
 * SampleImage.ets — 生成一张带假敏感信息的示例小票,
 * 让用户无需选择相册照片也能体验扫描流程(与 iOS 版 SampleImage 一致)。
 */

import { image } from '@kit.ImageKit';
import { LengthMetricsUnit } from '@kit.ArkUI';

export class SampleImage {
  static readonly WIDTH = 1170;
  static readonly HEIGHT = 1600;

  static make(): image.PixelMap {
    const w = SampleImage.WIDTH;
    const h = SampleImage.HEIGHT;
    const canvas = new OffscreenCanvas(w, h, LengthMetricsUnit.PX);
    const ctx = canvas.getContext('2d');

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, w, h);

    ctx.fillStyle = '#000000';
    ctx.font = 'bold 52px sans-serif';
    ctx.fillText('Invoice — ACME Store', 80, 172);

    const lines: string[] = [
      'Billed to: Michael Johnson',
      'Contact: john.doe@example.com',
      'Call +1 (555) 123-4567 today',
      'Ship to: 123 Main Street, Springfield',
      'Card: 4111 1111 1111 1111',
      'Order #: AB12345678',
      '订单号: SF1234567890',
      '收件人: 李小娜  电话 13812345678'
    ];
    ctx.font = '44px sans-serif';
    let y = 344;
    for (const line of lines) {
      ctx.fillText(line, 80, y);
      y += 130;
    }

    ctx.fillStyle = '#F0F0F0';
    ctx.fillRect(80, y + 20, 300, 60);
    ctx.fillStyle = '#888888';
    ctx.font = '32px sans-serif';
    ctx.fillText('DAMA sample', 100, y + 62);

    return ctx.getPixelMap(0, 0, w, h);
  }
}
