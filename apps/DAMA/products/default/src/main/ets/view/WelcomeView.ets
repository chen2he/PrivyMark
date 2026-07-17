/**
 * WelcomeView.ets — 首次启动引导(镜像 iOS WelcomeView):
 * 标签、大标题、检测能力示意卡、隐私承诺、CTA。
 */

import { Theme } from '../common/Theme';

@Component
export struct WelcomeView {
  onStart: () => void = () => {
  };

  build() {
    Column() {
      Column() {
        Text('欢迎')
          .fontSize(17)
          .fontColor(Theme.INK_SECONDARY)
          .margin({ top: 8 })
          .alignSelf(ItemAlign.Start)

        Text('找出图片里的\n隐私信息')
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .lineHeight(46)
          .margin({ top: 8 })
          .alignSelf(ItemAlign.Start)

        this.showcase()

        Column({ space: 14 }) {
          Text('DAMA 会自动找出照片中的隐私信息——人脸、电话、邮箱、姓名、卡号、证件号、车牌——并帮你一键遮盖。')
            .fontSize(17)
            .fontColor(Theme.INK_SECONDARY)
            .lineHeight(25)
          Text('识别全部在本机离线完成,你打开的任何图片都不会被上传。')
            .fontSize(17)
            .fontColor(Theme.INK_SECONDARY)
            .lineHeight(25)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 26 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('开始使用')
        .width('100%')
        .height(50)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(Theme.GREEN)
        .fontColor(Color.White)
        .onClick(() => {
          this.onStart();
        })
        .margin({ bottom: 16 })
    }
    .padding({ left: 26, right: 26, top: 20, bottom: 12 })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }

  @Builder
  showcase() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.badge('😀')
        this.chip('Alex Rivera')
        Blank()
      }

      Row({ space: 10 }) {
        this.chip('4393 1235 8893 4413')
        Blank()
        this.chip('¥1,000')
      }

      Row({ space: 12 }) {
        this.badge('▦')
        Column({ space: 8 }) {
          Row() {
            Blank()
            this.chip('steve@gmail.com')
          }.width('100%')

          Row() {
            Blank()
            this.chip('+86 138-1234-5678')
          }.width('100%')
        }
        .layoutWeight(1)
      }
    }
    .padding(16)
    .width('100%')
    .borderWidth(1)
    .borderColor(Theme.SEPARATOR)
    .borderRadius(18)
    .margin({ top: 26 })
  }

  @Builder
  badge(glyph: string) {
    Text(glyph)
      .fontSize(26)
      .width(56)
      .height(56)
      .textAlign(TextAlign.Center)
      .backgroundColor(Theme.GREEN_DIM)
      .borderRadius(14)
  }

  @Builder
  chip(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor(Theme.INK)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .backgroundColor(Theme.GREEN_DIM)
      .borderRadius(6)
  }
}
