/**
 * PrivacyPolicyView.ets — 隐私政策全文(本机内置,离线可读)。
 * 两种形态共用正文:设置页 push 的 HDS 二级页(PrivacyPolicyPage),
 * 以及首启隐私门内嵌的全屏视图(PrivacyGateView 在导航遮罩之上,不能走 push)。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { Theme } from '../common/Theme';

const TITLE_BAR_HEIGHT_MINI = 56;

class PolicySection {
  h: string = '';
  p: string = '';

  constructor(h: string, p: string) {
    this.h = h;
    this.p = p;
  }
}

const SECTIONS: PolicySection[] = [
  new PolicySection('一句话版本',
    'DAMA 不收集任何个人信息。你的图片完全在本机处理,绝不上传到任何地方,我们也不保留任何副本。应用没有账号系统、没有统计分析、没有广告、没有任何形式的追踪。'),
  new PolicySection('图片如何被处理',
    '识别、打码与导出全部通过 HarmonyOS 的端侧系统能力(Core Vision Kit 文字与人脸识别、Scan Kit 码识别)在本机离线完成。图片不会经由 DAMA 离开你的设备;我们没有服务器,应用也不申请网络权限。'),
  new PolicySection('权限',
    'DAMA 不申请相册读取权限:选图通过系统图库选择器完成,应用只能访问你主动选择的那一张图片;保存通过系统安全控件完成,只能写入你确认保存的那一张结果图。应用不使用相机、麦克风、定位或网络。'),
  new PolicySection('导出里的元数据',
    '导出时 DAMA 会把图片重新编码为新文件,原图携带的位置、拍摄设备、时间等元数据不会写入导出结果。'),
  new PolicySection('无追踪、无第三方 SDK',
    'DAMA 不含任何统计分析、广告或推送 SDK,不发送任何遥测数据,不存在包含你的图片或识别文本的崩溃报告。'),
  new PolicySection('不保留任何数据',
    'DAMA 没有历史记录,不保留你的图片副本。系统分享时的临时文件仅存放在应用私有沙箱内,并在下次分享时被覆盖。设置项(默认打码样式、默认水印文字)仅保存在本机。'),
  new PolicySection('儿童',
    'DAMA 不收集任何人的个人信息,包括儿童。'),
  new PolicySection('政策变更',
    '如本政策发生变化,更新版本会随应用新版本一同发布。鉴于应用什么都不收集,预期的变更极少且多为文字性修订。'),
  new PolicySection('联系我们',
    '开发者:jiamin.chen(个人开发者)。对隐私有任何疑问,请发邮件至 appstore@hz.do。')
];

@Builder
export function PrivacyPolicyPageBuilder() {
  PrivacyPolicyPage()
}

/** 正文卡片列表(两种形态共用)。 */
@Component
struct PolicyBody {
  build() {
    Column({ space: 14 }) {
      Text('最后更新:2026 年 7 月 13 日')
        .fontSize(12)
        .fontColor(Theme.INK_SECONDARY)
        .alignSelf(ItemAlign.Start)

      ForEach(SECTIONS, (s: PolicySection) => {
        Column({ space: 6 }) {
          Text(s.h)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK)
          Text(s.p)
            .fontSize(14)
            .fontColor(Theme.INK_SECONDARY)
            .lineHeight(22)
        }
        .padding(16)
        .width('100%')
        .backgroundColor(Theme.CARD)
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }, (s: PolicySection) => s.h)
    }
    .width('100%')
  }
}

/** 设置页 push 的 HDS 二级页。 */
@Component
struct PrivacyPolicyPage {
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          Column()
            .height(TITLE_BAR_HEIGHT_MINI)
            .width('100%')
          PolicyBody()
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
          mainTitle: '隐私政策'
        }
      }
    })
    .bindToScrollable([this.scroller])
    .backgroundColor(Theme.BG)
  }
}

/** 首启隐私门内嵌的全屏视图(带自绘返回栏)。 */
@Component
export struct PrivacyPolicyView {
  onBack: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        Button('‹ 返回')
          .fontSize(16)
          .fontColor(Theme.GREEN)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onBack();
          })
        Blank()
        Text('隐私政策')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK)
        Blank()
        Text('        ')
      }
      .width('100%')
      .padding({ top: 8, bottom: 8 })

      Scroll() {
        Column() {
          PolicyBody()
        }
        .padding({ bottom: 24 })
        .width('100%')
      }
      .layoutWeight(1)
    }
    .padding({ left: 20, right: 20 })
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
