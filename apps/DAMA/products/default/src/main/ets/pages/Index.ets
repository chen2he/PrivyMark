/**
 * Index.ets — 应用根(照 Teacher 项目的 HDS 架构):
 * HdsNavigation 包住首页,编辑器/设置/隐私政策经 route_map push 到根栈整页覆盖;
 * 隐私门与首启引导作为 Stack 遮罩盖在导航之上。
 */

import { HdsNavigation } from '@kit.UIDesignKit';
import { WelcomeView } from '../view/WelcomeView';
import { HomeView } from '../view/HomeView';
import { PrivacyGateView } from '../view/PrivacyGateView';
import { Nav } from '../common/Nav';
import { Theme } from '../common/Theme';

PersistentStorage.persistProp<boolean>('privacyAgreed', false);
PersistentStorage.persistProp<boolean>('hasSeenWelcome', false);
PersistentStorage.persistProp<string>('defaultStyle', 'block');
PersistentStorage.persistProp<string>('defaultWatermark', '仅供办理业务使用');

@Entry
@Component
struct Index {
  @StorageLink('privacyAgreed') privacyAgreed: boolean = false;
  @StorageLink('hasSeenWelcome') hasSeenWelcome: boolean = false;

  build() {
    Stack() {
      HdsNavigation(Nav.shared().stack) {
        HomeView()
      }
      .hideTitleBar(true)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.BG)

      // 首启引导遮罩(同意隐私政策之后、首次进入之前)
      if (this.privacyAgreed && !this.hasSeenWelcome) {
        WelcomeView({
          onStart: () => {
            this.hasSeenWelcome = true;
          }
        })
      }

      // 隐私门遮罩(最上层:未同意时优先于一切)
      if (!this.privacyAgreed) {
        PrivacyGateView({
          onAgree: () => {
            this.privacyAgreed = true;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
