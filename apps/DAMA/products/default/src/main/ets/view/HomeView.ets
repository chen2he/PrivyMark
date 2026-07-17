/**
 * HomeView.ets — 首页:选择照片(系统相册 Picker,无需权限)或试用示例图。
 * 选中后按预览分辨率解码进 EditorSession,再 push 编辑器。
 * HDS:HdsNavDestination 系统标题栏,设置入口在标题栏菜单。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { EditorSession } from '../service/EditorSession';
import { SampleImage } from '../service/SampleImage';

const DOMAIN = 0x0001;
const TAG = 'HomeView';
/** 预览/扫描用的长边上限(像素)。 */
const PREVIEW_MAX = 1600;
/** HDS mini 标题栏高度(内容顶部让位)。 */
const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct HomeView {
  @State loading: boolean = false;

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          Column()
            .height(TITLE_BAR_HEIGHT_MINI)
            .width('100%')

          Text('一键遮盖截图和照片里的隐私信息')
            .fontSize(16)
            .fontColor(Theme.INK_SECONDARY)
            .alignSelf(ItemAlign.Start)
            .margin({ top: 6 })

          Column({ space: 14 }) {
            Text('🖼️')
              .fontSize(52)
            Text('选一张图开始打码')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.INK)
            Text('人脸、电话、卡号、地址、二维码……\n自动识别,点一下就盖住')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .textAlign(TextAlign.Center)
              .lineHeight(21)

            Button('选择照片')
              .width(220)
              .height(48)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Theme.GREEN)
              .fontColor(Color.White)
              .onClick(() => {
                this.pickPhoto();
              })

            Button('试试示例图片')
              .width(220)
              .height(44)
              .fontSize(15)
              .backgroundColor(Color.Transparent)
              .fontColor(Theme.GREEN)
              .onClick(() => {
                this.openSample();
              })
          }
          .width('100%')
          .padding({ top: 44, bottom: 36 })
          .backgroundColor(Theme.CARD)
          .borderRadius(24)
          .margin({ top: 28 })

          Blank()

          Row({ space: 8 }) {
            Text('🔒')
              .fontSize(14)
            Text('所有识别均在本机离线完成,图片不会上传')
              .fontSize(13)
              .fontColor(Theme.INK_SECONDARY)
          }
          .margin({ bottom: 18 })
        }
        .padding({ left: 24, right: 24 })
        .width('100%')
        .height('100%')

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(44)
              .height(44)
              .color(Theme.GREEN)
            Text('正在载入图片…')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(255,255,255,0.85)')
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      content: {
        title: {
          mainTitle: 'DAMA'
        },
        menu: {
          value: [
            {
              content: {
                label: '设置',
                icon: $r('sys.symbol.gearshape'),
                action: () => {
                  Nav.push('SettingsPage');
                }
              }
            }
          ],
          maxCount: 1
        }
      }
    })
    .hideBackButton(true)
    .backgroundColor(Theme.BG)
  }

  private async pickPhoto(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      this.loading = true;
      await this.loadIntoSession(result.photoUris[0]);
      this.loading = false;
      Nav.push('EditorPage');
    } catch (e) {
      this.loading = false;
      hilog.error(DOMAIN, TAG, 'pick failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '图片载入失败,请重试' });
    }
  }

  private async loadIntoSession(uri: string): Promise<void> {
    const session = EditorSession.shared();
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const ow = info.size.width;
      const oh = info.size.height;
      const scale = Math.min(1, PREVIEW_MAX / Math.max(ow, oh));
      const pw = Math.max(1, Math.round(ow * scale));
      const ph = Math.max(1, Math.round(oh * scale));
      const opts: image.DecodingOptions = {
        desiredSize: { width: pw, height: ph },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      const map = await source.createPixelMap(opts);
      await source.release();
      session.reset();
      session.pixelMap = map;
      session.imgW = pw;
      session.imgH = ph;
      session.uri = uri;
      session.origW = ow;
      session.origH = oh;
    } finally {
      fs.closeSync(file);
    }
  }

  private openSample(): void {
    try {
      const session = EditorSession.shared();
      session.reset();
      session.pixelMap = SampleImage.make();
      session.imgW = SampleImage.WIDTH;
      session.imgH = SampleImage.HEIGHT;
      session.origW = SampleImage.WIDTH;
      session.origH = SampleImage.HEIGHT;
      Nav.push('EditorPage');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'sample failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '示例生成失败' });
    }
  }
}
