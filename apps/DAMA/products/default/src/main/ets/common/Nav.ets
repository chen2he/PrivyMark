/**
 * 根导航栈单例(照 Teacher 项目 Nav.ets)。HdsNavigation 在 Index 包住首页,
 * 二级页 push 到根栈后整页覆盖,返回自动恢复。
 */
export class Nav {
  private static instance: Nav | null = null;

  static shared(): Nav {
    if (Nav.instance === null) {
      Nav.instance = new Nav();
    }
    return Nav.instance;
  }

  readonly stack: NavPathStack = new NavPathStack();

  static push(name: string): void {
    Nav.shared().stack.pushPathByName(name, null);
  }

  static pop(): void {
    Nav.shared().stack.pop();
  }
}
