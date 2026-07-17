/**
 * PrivacyGateView.ets — 首次启动隐私政策提示(审核指南 7.5):
 * 弹窗式卡片,展示隐私要点 + 可点开《隐私政策》全文,
 * 同意后才进入应用;不同意则退出。
 */

import { common } from '@kit.AbilityKit';
import { Theme } from '../common/Theme';
import { PrivacyPolicyView } from './PrivacyPolicyView';

@Component
export struct PrivacyGateView {
  onAgree: () => void = () => {
  };
  @State showPolicy: boolean = false;

  build() {
    Stack() {
      if (this.showPolicy) {
        PrivacyPolicyView({
          onBack: () => {
            this.showPolicy = false;
          }
        })
      } else {
        // 半透明遮罩 + 居中弹窗卡片
        Column() {
          Column({ space: 14 }) {
            Text('欢迎使用 DAMA')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.INK)

            Text('感谢你使用 DAMA。在开始前,请阅读并了解我们的隐私政策:')
              .fontSize(14)
              .fontColor(Theme.INK_SECONDARY)
              .lineHeight(22)

            Text('· DAMA 不收集任何个人信息,没有账号、统计或广告\n· 图片识别与打码全部在本机离线完成,不会上传\n· 选图与保存均通过系统控件完成,应用不申请相册权限\n· 导出会重新编码图片,不携带位置等原图元数据')
              .fontSize(13)
              .fontColor(Theme.INK)
              .lineHeight(22)
              .padding(12)
              .backgroundColor(Theme.GREEN_DIM)
              .borderRadius(12)
              .width('100%')

            Text() {
              Span('点击「同意并继续」即表示你已阅读并同意')
                .fontSize(13)
                .fontColor(Theme.INK_SECONDARY)
              Span('《隐私政策》')
                .fontSize(13)
                .fontColor(Theme.GREEN)
                .onClick(() => {
                  this.showPolicy = true;
                })
              Span('。')
                .fontSize(13)
                .fontColor(Theme.INK_SECONDARY)
            }
            .width('100%')
            .onClick(() => {
              // 整行可点,保证审核/用户能稳定打开全文。
              this.showPolicy = true;
            })

            Button('同意并继续')
              .width('100%')
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Theme.GREEN)
              .fontColor(Color.White)
              .onClick(() => {
                this.onAgree();
              })

            Button('不同意并退出')
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(Color.Transparent)
              .fontColor(Theme.INK_SECONDARY)
              .onClick(() => {
                this.exitApp();
              })
          }
          .padding(22)
          .width('100%')
          .backgroundColor(Theme.BG)
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 24, right: 24 })
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.45)')
      }
    }
    .width('100%')
    .height('100%')
  }

  private exitApp(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.terminateSelf();
  }
}
