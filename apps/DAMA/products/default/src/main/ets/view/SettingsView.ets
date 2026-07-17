/**
 * SettingsView.ets — 设置页(HDS 二级页):默认打码样式、默认水印文字、关于与隐私承诺。
 * HdsNavDestination 系统标题栏 + 返回键,隐私政策 push 到根栈。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';

const TITLE_BAR_HEIGHT_MINI = 56;

@Builder
export function SettingsPageBuilder() {
  SettingsView()
}

@Component
export struct SettingsView {
  @StorageLink('defaultStyle') defaultStyle: string = 'block';
  @StorageLink('defaultWatermark') defaultWatermark: string = '仅供办理业务使用';
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column()
            .height(TITLE_BAR_HEIGHT_MINI)
            .width('100%')

          Column({ space: 10 }) {
            Text('默认打码样式')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
            Row({ space: 10 }) {
              this.styleChip('block', '色块')
              this.styleChip('pixelate', '马赛克')
              this.styleChip('blur', '模糊')
            }
            .width('100%')

            Text('色块不可逆、最安全;马赛克和模糊对文字有被还原的风险。')
              .fontSize(12)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            Text('默认水印文字')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
            TextInput({ text: this.defaultWatermark, placeholder: '例如:仅供办理业务使用' })
              .fontSize(15)
              .backgroundColor(Theme.BG)
              .onChange((v: string) => {
                this.defaultWatermark = v;
              })
            Text('在编辑器里开启「水印」工具时,默认平铺这段文字。')
              .fontSize(12)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('隐私承诺')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
            Text('· 人脸与文字识别全部调用系统本机能力,离线完成\n· 你打开的图片不会被上传,应用不含任何统计埋点\n· 导出会重新编码图片,自动移除位置等全部元数据')
              .fontSize(14)
              .fontColor(Theme.INK)
              .lineHeight(24)
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.GREEN_DIM)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          Row() {
            Text('隐私政策')
              .fontSize(15)
              .fontColor(Theme.INK)
            Blank()
            Text('›')
              .fontSize(18)
              .fontColor(Theme.INK_SECONDARY)
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .onClick(() => {
            Nav.push('PrivacyPolicyPage');
          })

          Column({ space: 6 }) {
            Text('关于')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .alignSelf(ItemAlign.Start)
            Text('DAMA(打码)· HarmonyOS 版 1.0.2')
              .fontSize(14)
              .fontColor(Theme.INK)
            Text('与 iOS 版 PrivyMark 同源的本机隐私打码工具。')
              .fontSize(13)
              .fontColor(Theme.INK_SECONDARY)
          }
          .padding(16)
          .width('100%')
          .backgroundColor(Theme.CARD)
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 20, right: 20, bottom: 24 })
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
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
          mainTitle: '设置'
        }
      }
    })
    .bindToScrollable([this.scroller])
    .backgroundColor(Theme.BG)
  }

  @Builder
  styleChip(key: string, label: string) {
    Text(label)
      .fontSize(15)
      .fontColor(this.defaultStyle === key ? Color.White : Theme.INK)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.defaultStyle === key ? Theme.GREEN : Theme.BG)
      .borderRadius(20)
      .onClick(() => {
        this.defaultStyle = key;
      })
  }
}
