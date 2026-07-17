/**
 * EditorSession.ets — 首页与编辑器之间传递图像的单例
 * (PixelMap 不能通过路由参数传递)。
 */

import { image } from '@kit.ImageKit';

export class EditorSession {
  private static instance: EditorSession | null = null;

  /** 预览分辨率的源图(长边 ≤ 1600px,扫描与预览都用它)。 */
  pixelMap: image.PixelMap | null = null;
  /** 预览源图的像素尺寸。 */
  imgW: number = 0;
  imgH: number = 0;
  /** 相册图片的 URI;示例图为空串。导出时按它重新解码全分辨率。 */
  uri: string = '';
  /** 原图像素尺寸(条码框归一化 + 全分辨率导出用)。 */
  origW: number = 0;
  origH: number = 0;

  static shared(): EditorSession {
    if (EditorSession.instance === null) {
      EditorSession.instance = new EditorSession();
    }
    return EditorSession.instance;
  }

  reset(): void {
    this.pixelMap = null;
    this.imgW = 0;
    this.imgH = 0;
    this.uri = '';
    this.origW = 0;
    this.origH = 0;
  }
}
