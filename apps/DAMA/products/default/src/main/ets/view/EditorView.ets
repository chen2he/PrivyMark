/**
 * EditorView.ets — 编辑器(镜像 iOS EditorView 的基础形态):
 *  - 画布预览:渲染结果所见即所得(与导出同一条渲染路径)。
 *  - 自动扫描:进入即离线识别人脸 / 文字 / 条码。
 *  - 手势:点按 = 逐层取消或恢复覆盖;拖动 = 手动框选 / 涂鸦;长按 = 文字大爆炸。
 *  - 工具:自动 / 色块 / 马赛克 / 模糊 / 涂鸦 / 水印 + 色板。
 *  - 导出:保存副本到相册(安全控件,免权限弹窗)或系统分享,重新编码去元数据。
 */

import { LengthMetrics } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';
import { Nav } from '../common/Nav';
import { NRect, OcrLine, OcrWord, RedactionStyle, RiskLevel, RiskRegion, RiskType, Stroke,
  riskLevelName, riskTypeName } from '../model/Models';
import { EditorSession } from '../service/EditorSession';
import { RedactionRenderer, RenderInput } from '../service/RedactionRenderer';
import { ScanService } from '../service/ScanService';

const DOMAIN = 0x0001;
const TAG = 'EditorView';
/** 导出时全分辨率解码的长边上限。 */
const EXPORT_MAX = 4096;

/** 撤销栈快照。 */
class Snapshot {
  regions: RiskRegion[] = [];
  strokes: Stroke[] = [];
  watermarkOn: boolean = false;
  watermarkText: string = '';
}

@Builder
export function EditorPageBuilder() {
  EditorView()
}

@Component
export struct EditorView {
  // —— 文档状态 ——
  @State regions: RiskRegion[] = [];
  @State strokes: Stroke[] = [];
  @State lines: OcrLine[] = [];
  @State style: string = 'block';
  @State blockColor: string = '#000000';
  @State markerColor: string = '#000000';
  @State watermarkOn: boolean = false;
  @State watermarkText: string = '';
  @State tool: string = 'style'; // 'style' | 'marker'
  // —— 运行状态 ——
  // 初始必须为 false:startScan 开头有 this.scanning 防重入守卫,
  // 初始 true 会让 aboutToAppear 的入场自动扫描被守卫直接吃掉。
  @State scanning: boolean = false;
  @State scanSummary: string = '';
  @State undoDepth: number = 0;
  @State redoDepth: number = 0;
  // —— 面板 ——
  @State showRisk: boolean = false;
  @State showExport: boolean = false;
  @State showExplode: boolean = false;
  @State showEmoji: boolean = false;
  @State showWatermark: boolean = false;
  @State explodeLineIndex: number = -1;
  @State emojiRegionId: number = -1;
  @State exportReady: boolean = false;
  @State exportStatus: string = '';
  // —— 画布 ——
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private previewMap: image.PixelMap | null = null;
  private session: EditorSession = EditorSession.shared();
  private undoStack: Snapshot[] = [];
  private redoStack: Snapshot[] = [];
  private exportBuf: ArrayBuffer | null = null;
  // 拖动中的手动框(归一化)/ 涂鸦
  private dragStartX: number = -1;
  private dragStartY: number = -1;
  private dragCurX: number = -1;
  private dragCurY: number = -1;
  private liveStroke: Stroke | null = null;

  aboutToAppear(): void {
    const defStyle = AppStorage.get<string>('defaultStyle');
    if (defStyle !== undefined) {
      this.style = defStyle;
    }
    const defWm = AppStorage.get<string>('defaultWatermark');
    this.watermarkText = defWm !== undefined && defWm.length > 0 ? defWm : '仅供办理业务使用';
    this.startScan();
  }

  /** 关闭编辑器:释放会话再弹栈(与旧 Index onClose 语义一致)。 */
  private close(): void {
    EditorSession.shared().reset();
    Nav.pop();
  }

  build() {
    HdsNavDestination() {
    Column() {
      this.TopBar()

      Stack() {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.EDITOR_BG)
          .onReady(() => {
            this.redraw();
          })
          .gesture(GestureGroup(GestureMode.Exclusive,
            LongPressGesture({ repeat: false })
              .onAction((event: GestureEvent) => {
                this.handleLongPress(event);
              }),
            PanGesture({ distance: 4 })
              .onActionStart((event: GestureEvent) => {
                this.handlePanStart(event);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.handlePanUpdate(event);
              })
              .onActionEnd(() => {
                this.handlePanEnd();
              }),
            TapGesture({ count: 1 })
              .onAction((event: GestureEvent) => {
                this.handleTap(event);
              })
          ))
          .bindSheet($$this.showExplode, this.ExplodeSheet(), {
            height: 420,
            title: { title: '文字大爆炸', subtitle: '点选词块即可盖住' }
          })
          .bindSheet($$this.showEmoji, this.EmojiSheet(), {
            height: 360,
            title: { title: '人脸表情' }
          })

        if (this.scanning) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(46)
              .height(46)
              .color(Theme.GREEN)
            Text('正在离线识别隐私信息…')
              .fontSize(14)
              .fontColor(Color.White)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.45)')
        }
      }
      .layoutWeight(1)
      .clip(true)

      this.ToolPalette()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.EDITOR_BG)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onBackPressed(() => {
      // 系统返回/侧滑:与 ✕ 一致,先释放会话再交给导航弹栈
      EditorSession.shared().reset();
      return false;
    })
    .backgroundColor(Theme.EDITOR_BG)
  }

  // ================== 顶栏 ==================

  @Builder
  TopBar() {
    Row({ space: 6 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(19)
          .fontColor([Color.White])
      }
      .backgroundColor('rgba(255,255,255,0.12)')
      .width(38)
      .height(38)
      .onClick(() => {
        this.close();
      })

      Blank()

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(19)
          .fontColor([this.undoDepth > 0 ? Color.White : 'rgba(255,255,255,0.3)'])
      }
      .backgroundColor('rgba(255,255,255,0.12)')
      .width(38)
      .height(38)
      .onClick(() => {
        this.undo();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(19)
          .fontColor([this.redoDepth > 0 ? Color.White : 'rgba(255,255,255,0.3)'])
      }
      .backgroundColor('rgba(255,255,255,0.12)')
      .width(38)
      .height(38)
      .onClick(() => {
        this.redo();
      })

      Button('风险 ' + this.selectedCount() + '/' + this.regions.length)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('rgba(255,255,255,0.12)')
        .height(38)
        .onClick(() => {
          this.showRisk = true;
        })
        .bindSheet($$this.showRisk, this.RiskSheet(), {
          height: 520,
          title: { title: '识别结果', subtitle: '开关控制每一处覆盖' }
        })

      Button('导出')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(Theme.GREEN)
        .height(38)
        .onClick(() => {
          this.openExport();
        })
        .bindSheet($$this.showExport, this.ExportSheet(), {
          height: 380,
          title: { title: '导出' }
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  // ================== 工具条 ==================

  @Builder
  ToolPalette() {
    Column({ space: 8 }) {
      if (this.tool === 'marker' || this.style === 'block') {
        Row({ space: 8 }) {
          ForEach(Theme.SWATCHES, (c: string) => {
            Text('')
              .width(26)
              .height(26)
              .backgroundColor(c)
              .borderRadius(13)
              .borderWidth(this.activeColor() === c ? 3 : 1)
              .borderColor(this.activeColor() === c ? Theme.GREEN : 'rgba(255,255,255,0.4)')
              .onClick(() => {
                this.pickColor(c);
              })
          }, (c: string) => c + '-' + this.activeColor())
        }
        .padding({ top: 2, bottom: 2 })
      }

      Scroll() {
        Row({ space: 8 }) {
          this.toolChip('auto', '自动')
          this.toolChip('block', '色块')
          this.toolChip('pixelate', '马赛克')
          this.toolChip('blur', '模糊')
          this.toolChip('marker', '涂鸦')
          this.toolChip('watermark', '水印')
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Text('点按取消/恢复覆盖 · 拖动手动框选 · 长按整行拆词')
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.45)')
    }
    .width('100%')
    .padding({ top: 10, bottom: 14 })
    .backgroundColor('rgba(255,255,255,0.06)')
    .bindSheet($$this.showWatermark, this.WatermarkSheet(), {
      height: 320,
      title: { title: '水印' }
    })
  }

  /**
   * 注意:@Builder 按值传参不会触发刷新,选中态必须在 builder 体内
   * 通过 chipActive(key) 读取 @State 计算。
   */
  private chipActive(key: string): boolean {
    if (key === 'marker') {
      return this.tool === 'marker';
    }
    if (key === 'watermark') {
      return this.watermarkOn;
    }
    if (key === 'auto') {
      // 有自动识别区域处于覆盖状态时点亮,提示再点可整体取消
      for (const r of this.regions) {
        if (!r.manual && r.selected) {
          return true;
        }
      }
      return false;
    }
    return this.tool !== 'marker' && this.style === key;
  }

  @Builder
  toolChip(key: string, label: string) {
    Text(key === 'watermark' && this.watermarkOn ? label + ' ✓' : label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chipActive(key) ? Color.Black : Color.White)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.chipActive(key) ? Theme.GREEN : 'rgba(255,255,255,0.14)')
      .borderRadius(18)
      .onClick(() => {
        this.onToolTap(key);
      })
  }

  // ================== 面板 ==================

  @Builder
  RiskSheet() {
    Column() {
      Row({ space: 10 }) {
        Button('全部覆盖')
          .fontSize(13)
          .height(32)
          .backgroundColor(Theme.GREEN)
          .fontColor(Color.White)
          .onClick(() => {
            this.setAll(true);
          })
        Button('全部取消')
          .fontSize(13)
          .height(32)
          .backgroundColor(Theme.CARD)
          .fontColor(Theme.INK)
          .onClick(() => {
            this.setAll(false);
          })
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      List({ space: 2 }) {
        ForEach(this.sortedRegions(), (r: RiskRegion) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(riskTypeName(r.type))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.INK)
                  Text(riskLevelName(r.level))
                    .fontSize(11)
                    .fontColor(r.level === RiskLevel.HIGH ? Color.White : Theme.INK_SECONDARY)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor(r.level === RiskLevel.HIGH ? Theme.DANGER : Theme.CARD)
                    .borderRadius(4)
                }

                if (r.detectedText.length > 0) {
                  Text(r.detectedText)
                    .fontSize(12)
                    .fontColor(Theme.INK_SECONDARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: r.selected })
                .selectedColor(Theme.GREEN)
                .onChange((on: boolean) => {
                  if (on !== r.selected) {
                    this.pushSnapshot();
                    r.selected = on;
                    this.commitRegions();
                  }
                })
            }
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          }
        }, (r: RiskRegion) => r.id + '-' + (r.selected ? '1' : '0'))
      }
      .layoutWeight(1)
    }
    .padding({ top: 4 })
  }

  @Builder
  ExplodeSheet() {
    Column({ space: 12 }) {
      if (this.explodeLineIndex >= 0 && this.explodeLineIndex < this.lines.length) {
        Text(this.lines[this.explodeLineIndex].text)
          .fontSize(13)
          .fontColor(Theme.INK_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Button('盖住整行')
          .fontSize(14)
          .height(36)
          .backgroundColor(Theme.GREEN)
          .fontColor(Color.White)
          .onClick(() => {
            this.coverWholeLine();
          })

        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
            ForEach(this.lines[this.explodeLineIndex].words, (w: OcrWord, idx: number) => {
              this.wordChip(this.explodeLineIndex, idx)
            }, (w: OcrWord, idx: number) => this.explodeLineIndex + '-' + idx + '-' +
              (this.isWordCovered(this.explodeLineIndex, idx) ? '1' : '0'))
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  @Builder
  wordChip(lineIdx: number, wordIdx: number) {
    Text(this.lines[lineIdx].words[wordIdx].text)
      .fontSize(14)
      .fontColor(this.isWordCovered(lineIdx, wordIdx) ? Color.White : Theme.INK)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.isWordCovered(lineIdx, wordIdx) ? Theme.INK : Theme.CARD)
      .borderRadius(8)
      .onClick(() => {
        this.toggleWordCover(lineIdx, wordIdx);
      })
  }

  @Builder
  EmojiSheet() {
    Column({ space: 16 }) {
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(10) } }) {
        ForEach(Theme.EMOJIS, (e: string) => {
          Text(e)
            .fontSize(30)
            .width(52)
            .height(52)
            .textAlign(TextAlign.Center)
            .backgroundColor(Theme.CARD)
            .borderRadius(12)
            .onClick(() => {
              this.setEmoji(e);
            })
        }, (e: string) => e)
      }
      .width('100%')

      Button('取消这张脸的覆盖')
        .fontSize(14)
        .height(38)
        .backgroundColor(Theme.CARD)
        .fontColor(Theme.DANGER)
        .onClick(() => {
          this.uncoverEmojiRegion();
        })
    }
    .padding(16)
    .width('100%')
  }

  @Builder
  WatermarkSheet() {
    Column({ space: 14 }) {
      Row() {
        Text('平铺水印')
          .fontSize(16)
          .fontColor(Theme.INK)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.watermarkOn })
          .selectedColor(Theme.GREEN)
          .onChange((on: boolean) => {
            if (on !== this.watermarkOn) {
              this.pushSnapshot();
              this.watermarkOn = on;
              this.refresh();
            }
          })
      }
      .width('100%')

      TextInput({ text: this.watermarkText, placeholder: '水印文字' })
        .fontSize(15)
        .onChange((v: string) => {
          this.watermarkText = v;
        })
        .onSubmit(() => {
          this.refresh();
        })

      Button('应用文字')
        .fontSize(14)
        .height(36)
        .backgroundColor(Theme.GREEN)
        .fontColor(Color.White)
        .onClick(() => {
          if (!this.watermarkOn) {
            this.watermarkOn = true;
          }
          this.refresh();
          this.showWatermark = false;
        })

      Text('例如「仅供办理入职使用」。水印会平铺在整张图上,导出即固化。')
        .fontSize(12)
        .fontColor(Theme.INK_SECONDARY)
    }
    .padding(16)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ExportSheet() {
    Column({ space: 14 }) {
      Text('导出会重新编码图片,自动移除位置等全部元数据;所有处理均在本机完成。')
        .fontSize(13)
        .fontColor(Theme.INK_SECONDARY)
        .width('100%')

      if (!this.exportReady) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(Theme.GREEN)
          Text(this.exportStatus.length > 0 ? this.exportStatus : '正在按原始分辨率渲染…')
            .fontSize(14)
            .fontColor(Theme.INK)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 20, bottom: 20 })
      } else {
        SaveButton({
          icon: SaveIconStyle.FULL_FILLED,
          text: SaveDescription.SAVE_IMAGE,
          buttonType: ButtonType.Capsule
        })
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor(Theme.GREEN)
          .fontColor(Color.White)
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            this.saveToAlbum(result);
          })

        Button('系统分享')
          .width('100%')
          .height(44)
          .fontSize(15)
          .backgroundColor(Theme.CARD)
          .fontColor(Theme.INK)
          .onClick(() => {
            this.shareImage();
          })
      }

      Text(this.watermarkOn ? '将包含平铺水印:' + this.watermarkText : '未开启水印')
        .fontSize(12)
        .fontColor(Theme.INK_SECONDARY)
    }
    .padding(16)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ================== 扫描 ==================

  /** 自动扫描。重扫时保留手动框选/涂鸦,只替换自动识别的区域。 */
  private async startScan(): Promise<void> {
    if (this.session.pixelMap === null || this.scanning) {
      this.scanning = false;
      return;
    }
    this.scanning = true;
    try {
      const out = await ScanService.scan(this.session.pixelMap, this.session.imgW, this.session.imgH,
        this.session.uri, this.session.origW, this.session.origH);
      const manual = this.regions.filter((r: RiskRegion) => r.manual);
      this.regions = out.regions.concat(manual);
      this.lines = out.lines;
      const auto = out.regions.length;
      const n = this.selectedCount();
      this.scanSummary = auto > 0 ? ('识别到 ' + auto + ' 处,已覆盖 ' + n + ' 处')
        : '未发现明显隐私信息,可拖动手动框选';
      this.getUIContext().getPromptAction().showToast({ message: this.scanSummary });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'scan failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '识别失败,可点「自动」重试或拖动手动框选' });
    }
    this.scanning = false;
    this.refresh();
  }

  // ================== 渲染 ==================

  private renderInput(): RenderInput {
    const input = new RenderInput();
    input.regions = this.regions;
    input.strokes = this.strokes;
    input.style = this.style === 'pixelate' ? RedactionStyle.PIXELATE :
      (this.style === 'blur' ? RedactionStyle.BLUR : RedactionStyle.BLOCK);
    input.blockColor = this.blockColor;
    input.watermarkText = this.watermarkOn ? this.watermarkText : '';
    return input;
  }

  private refresh(): void {
    if (this.session.pixelMap === null) {
      return;
    }
    try {
      this.previewMap = RedactionRenderer.render(this.session.pixelMap,
        this.session.imgW, this.session.imgH, this.renderInput());
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'render failed: %{public}s', JSON.stringify(e));
    }
    this.redraw();
  }

  /** 画布上的图像显示区(vp):[x, y, w, h]。 */
  private fitRect(): number[] {
    const cw = this.ctx.width;
    const ch = this.ctx.height;
    const iw = this.session.imgW;
    const ih = this.session.imgH;
    if (cw <= 0 || ch <= 0 || iw <= 0 || ih <= 0) {
      return [0, 0, 0, 0];
    }
    const scale = Math.min(cw / iw, ch / ih);
    const fw = iw * scale;
    const fh = ih * scale;
    return [(cw - fw) / 2, (ch - fh) / 2, fw, fh];
  }

  private redraw(): void {
    const f = this.fitRect();
    if (f[2] <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.ctx.width, this.ctx.height);
    if (this.previewMap !== null) {
      this.ctx.drawImage(this.previewMap, f[0], f[1], f[2], f[3]);
    } else if (this.session.pixelMap !== null) {
      this.ctx.drawImage(this.session.pixelMap, f[0], f[1], f[2], f[3]);
    }

    // 未覆盖的候选区域画绿色虚线框,提示可点按恢复。
    this.ctx.save();
    this.ctx.setLineDash([6, 4]);
    this.ctx.strokeStyle = Theme.GREEN;
    this.ctx.lineWidth = 1.5;
    for (const r of this.regions) {
      if (r.selected) {
        continue;
      }
      this.ctx.strokeRect(f[0] + r.box.x * f[2], f[1] + r.box.y * f[3],
        r.box.w * f[2], r.box.h * f[3]);
    }
    this.ctx.restore();

    // 拖动中的手动框。
    if (this.dragStartX >= 0 && this.tool !== 'marker') {
      const x = Math.min(this.dragStartX, this.dragCurX);
      const y = Math.min(this.dragStartY, this.dragCurY);
      const w = Math.abs(this.dragCurX - this.dragStartX);
      const h = Math.abs(this.dragCurY - this.dragStartY);
      this.ctx.save();
      this.ctx.setLineDash([6, 4]);
      this.ctx.strokeStyle = '#FFFFFF';
      this.ctx.lineWidth = 2;
      this.ctx.strokeRect(f[0] + x * f[2], f[1] + y * f[3], w * f[2], h * f[3]);
      this.ctx.restore();
    }

    // 涂鸦中的实时笔迹。
    if (this.liveStroke !== null && this.liveStroke.points.length >= 4) {
      const s = this.liveStroke;
      this.ctx.save();
      this.ctx.strokeStyle = s.color;
      this.ctx.lineWidth = Math.max(2, s.width * f[2]);
      this.ctx.lineCap = 'round';
      this.ctx.lineJoin = 'round';
      this.ctx.beginPath();
      this.ctx.moveTo(f[0] + s.points[0] * f[2], f[1] + s.points[1] * f[3]);
      for (let i = 2; i < s.points.length; i += 2) {
        this.ctx.lineTo(f[0] + s.points[i] * f[2], f[1] + s.points[i + 1] * f[3]);
      }
      this.ctx.stroke();
      this.ctx.restore();
    }
  }

  // ================== 手势 ==================

  /** 触点 → 归一化图像坐标;不在图内返回 null。 */
  private norm(event: GestureEvent): number[] | null {
    if (event.fingerList.length === 0) {
      return null;
    }
    const f = this.fitRect();
    if (f[2] <= 0) {
      return null;
    }
    const nx = (event.fingerList[0].localX - f[0]) / f[2];
    const ny = (event.fingerList[0].localY - f[1]) / f[3];
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) {
      return null;
    }
    return [nx, ny];
  }

  private handleTap(event: GestureEvent): void {
    const p = this.norm(event);
    if (p === null) {
      return;
    }
    // 已覆盖区域:优先「剥离」最小的一块;人脸改为打开表情面板。
    let hitSelected: RiskRegion | null = null;
    let hitUnselected: RiskRegion | null = null;
    for (const r of this.regions) {
      if (!r.box.contains(p[0], p[1])) {
        continue;
      }
      if (r.selected) {
        if (hitSelected === null || r.box.area() < hitSelected.box.area()) {
          hitSelected = r;
        }
      } else {
        if (hitUnselected === null || r.box.area() < hitUnselected.box.area()) {
          hitUnselected = r;
        }
      }
    }
    if (hitSelected !== null) {
      if (hitSelected.emoji.length > 0) {
        this.emojiRegionId = hitSelected.id;
        this.showEmoji = true;
        return;
      }
      this.pushSnapshot();
      hitSelected.selected = false;
      this.commitRegions();
      return;
    }
    if (hitUnselected !== null) {
      this.pushSnapshot();
      hitUnselected.selected = true;
      this.commitRegions();
    }
  }

  private handleLongPress(event: GestureEvent): void {
    const p = this.norm(event);
    if (p === null) {
      return;
    }
    let best = -1;
    let bestArea = Number.MAX_VALUE;
    for (let i = 0; i < this.lines.length; i++) {
      const line = this.lines[i];
      if (line.rect.contains(p[0], p[1]) && line.rect.area() < bestArea) {
        best = i;
        bestArea = line.rect.area();
      }
    }
    if (best >= 0) {
      this.explodeLineIndex = best;
      this.showExplode = true;
    }
  }

  private handlePanStart(event: GestureEvent): void {
    const p = this.norm(event);
    if (p === null) {
      return;
    }
    if (this.tool === 'marker') {
      const s = new Stroke(0.018, this.markerColor);
      s.points.push(p[0]);
      s.points.push(p[1]);
      this.liveStroke = s;
    } else {
      this.dragStartX = p[0];
      this.dragStartY = p[1];
      this.dragCurX = p[0];
      this.dragCurY = p[1];
    }
  }

  private handlePanUpdate(event: GestureEvent): void {
    const p = this.norm(event);
    if (p === null) {
      return;
    }
    if (this.tool === 'marker' && this.liveStroke !== null) {
      this.liveStroke.points.push(p[0]);
      this.liveStroke.points.push(p[1]);
    } else if (this.dragStartX >= 0) {
      this.dragCurX = p[0];
      this.dragCurY = p[1];
    }
    this.redraw();
  }

  private handlePanEnd(): void {
    if (this.tool === 'marker' && this.liveStroke !== null) {
      if (this.liveStroke.points.length >= 4) {
        this.pushSnapshot();
        this.strokes.push(this.liveStroke);
        this.strokes = this.strokes.slice();
      }
      this.liveStroke = null;
      this.refresh();
      return;
    }
    if (this.dragStartX >= 0) {
      const x = Math.min(this.dragStartX, this.dragCurX);
      const y = Math.min(this.dragStartY, this.dragCurY);
      const w = Math.abs(this.dragCurX - this.dragStartX);
      const h = Math.abs(this.dragCurY - this.dragStartY);
      this.dragStartX = -1;
      this.dragStartY = -1;
      if (w > 0.015 && h > 0.008) {
        this.pushSnapshot();
        const r = new RiskRegion(RiskType.OTHER_TEXT, new NRect(x, y, w, h),
          RiskLevel.MEDIUM, '手动框选', 1, true);
        r.selected = true;
        this.regions.push(r);
        this.commitRegions();
        return;
      }
      this.redraw();
    }
  }

  // ================== 工具 ==================

  private onToolTap(key: string): void {
    if (key === 'auto') {
      if (this.scanning) {
        return;
      }
      this.tool = 'style';
      let hasAuto = false;
      let hasCovered = false;
      for (const r of this.regions) {
        if (!r.manual) {
          hasAuto = true;
          if (r.selected) {
            hasCovered = true;
          }
        }
      }
      if (!hasAuto) {
        // 没有自动区域(此前无结果或识别失败):重新扫描一次。
        this.startScan();
        return;
      }
      this.pushSnapshot();
      if (hasCovered) {
        // 反转:整体取消自动识别区域的覆盖(手动框选/涂鸦不受影响)。
        let cleared = 0;
        for (const r of this.regions) {
          if (!r.manual && r.selected) {
            r.selected = false;
            cleared++;
          }
        }
        this.commitRegions();
        this.getUIContext().getPromptAction().showToast({
          message: '已取消 ' + cleared + ' 处自动识别的覆盖,再点「自动」可恢复'
        });
        return;
      }
      let restored = 0;
      for (const r of this.regions) {
        if (!r.manual) {
          r.selected = r.level > RiskLevel.LOW;
          if (r.selected) {
            restored++;
          }
        }
      }
      this.commitRegions();
      this.getUIContext().getPromptAction().showToast({
        message: restored > 0 ? ('已恢复 ' + restored + ' 处自动识别的覆盖')
          : '自动识别的均为疑似项,可在「风险」面板逐项开启'
      });
      return;
    }
    if (key === 'marker') {
      this.tool = this.tool === 'marker' ? 'style' : 'marker';
      return;
    }
    if (key === 'watermark') {
      this.showWatermark = true;
      return;
    }
    // block / pixelate / blur:切换全局样式。
    this.pushSnapshot();
    this.style = key;
    this.tool = 'style';
    this.refresh();
  }

  private activeColor(): string {
    return this.tool === 'marker' ? this.markerColor : this.blockColor;
  }

  private pickColor(c: string): void {
    if (this.tool === 'marker') {
      this.markerColor = c;
    } else {
      this.pushSnapshot();
      this.blockColor = c;
      this.refresh();
    }
  }

  // ================== 区域操作 ==================

  private selectedCount(): number {
    let n = 0;
    for (const r of this.regions) {
      if (r.selected) {
        n++;
      }
    }
    return n;
  }

  private sortedRegions(): RiskRegion[] {
    const copy = this.regions.slice();
    copy.sort((a, b) => b.level - a.level);
    return copy;
  }

  private commitRegions(): void {
    this.regions = this.regions.slice();
    this.refresh();
  }

  private setAll(on: boolean): void {
    this.pushSnapshot();
    for (const r of this.regions) {
      r.selected = on;
    }
    this.commitRegions();
  }

  private setEmoji(e: string): void {
    this.pushSnapshot();
    for (const r of this.regions) {
      if (r.id === this.emojiRegionId) {
        r.emoji = e;
        r.selected = true;
      }
    }
    this.showEmoji = false;
    this.commitRegions();
  }

  private uncoverEmojiRegion(): void {
    this.pushSnapshot();
    for (const r of this.regions) {
      if (r.id === this.emojiRegionId) {
        r.selected = false;
      }
    }
    this.showEmoji = false;
    this.commitRegions();
  }

  private wordRegionIndex(lineIdx: number, wordIdx: number): number {
    const rect = this.lines[lineIdx].words[wordIdx].rect;
    for (let i = 0; i < this.regions.length; i++) {
      const r = this.regions[i];
      if (r.manual && NRect.iou(r.box, rect) > 0.85) {
        return i;
      }
    }
    return -1;
  }

  private isWordCovered(lineIdx: number, wordIdx: number): boolean {
    const i = this.wordRegionIndex(lineIdx, wordIdx);
    return i >= 0 && this.regions[i].selected;
  }

  private toggleWordCover(lineIdx: number, wordIdx: number): void {
    this.pushSnapshot();
    const i = this.wordRegionIndex(lineIdx, wordIdx);
    if (i >= 0) {
      this.regions.splice(i, 1);
    } else {
      const w = this.lines[lineIdx].words[wordIdx];
      const r = new RiskRegion(RiskType.OTHER_TEXT, w.rect.clone(), RiskLevel.MEDIUM, w.text, 1, true);
      r.selected = true;
      this.regions.push(r);
    }
    this.commitRegions();
  }

  private coverWholeLine(): void {
    if (this.explodeLineIndex < 0) {
      return;
    }
    this.pushSnapshot();
    const line = this.lines[this.explodeLineIndex];
    const r = new RiskRegion(RiskType.OTHER_TEXT, line.rect.clone(), RiskLevel.MEDIUM, line.text, 1, true);
    r.selected = true;
    this.regions.push(r);
    this.showExplode = false;
    this.commitRegions();
  }

  // ================== 撤销 / 重做 ==================

  private makeSnapshot(): Snapshot {
    const s = new Snapshot();
    s.regions = this.regions.map((r: RiskRegion) => r.clone());
    s.strokes = this.strokes.map((k: Stroke) => k.clone());
    s.watermarkOn = this.watermarkOn;
    s.watermarkText = this.watermarkText;
    return s;
  }

  private applySnapshot(s: Snapshot): void {
    this.regions = s.regions.map((r: RiskRegion) => r.clone());
    this.strokes = s.strokes.map((k: Stroke) => k.clone());
    this.watermarkOn = s.watermarkOn;
    this.watermarkText = s.watermarkText;
    this.refresh();
  }

  private pushSnapshot(): void {
    this.undoStack.push(this.makeSnapshot());
    if (this.undoStack.length > 20) {
      this.undoStack.shift();
    }
    this.redoStack = [];
    this.undoDepth = this.undoStack.length;
    this.redoDepth = 0;
  }

  private undo(): void {
    const s = this.undoStack.pop();
    if (s === undefined) {
      return;
    }
    this.redoStack.push(this.makeSnapshot());
    this.applySnapshot(s);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  }

  private redo(): void {
    const s = this.redoStack.pop();
    if (s === undefined) {
      return;
    }
    this.undoStack.push(this.makeSnapshot());
    this.applySnapshot(s);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
  }

  // ================== 导出 ==================

  private openExport(): void {
    this.exportReady = false;
    this.exportBuf = null;
    this.showExport = true;
    this.prepareExport();
  }

  /** 按原始分辨率重新渲染并编码(与预览同一路径,归一化区域天然适配)。 */
  private async prepareExport(): Promise<void> {
    try {
      let srcMap: image.PixelMap | null = null;
      let w = this.session.imgW;
      let h = this.session.imgH;
      let transient = false;
      if (this.session.uri.length > 0) {
        this.exportStatus = '正在按原始分辨率渲染…';
        const file = fs.openSync(this.session.uri, fs.OpenMode.READ_ONLY);
        try {
          const source = image.createImageSource(file.fd);
          const scale = Math.min(1, EXPORT_MAX / Math.max(this.session.origW, this.session.origH));
          w = Math.max(1, Math.round(this.session.origW * scale));
          h = Math.max(1, Math.round(this.session.origH * scale));
          const opts: image.DecodingOptions = {
            desiredSize: { width: w, height: h },
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          };
          srcMap = await source.createPixelMap(opts);
          await source.release();
          transient = true;
        } finally {
          fs.closeSync(file);
        }
      } else {
        srcMap = this.session.pixelMap;
      }
      if (srcMap === null) {
        return;
      }
      const rendered = RedactionRenderer.render(srcMap, w, h, this.renderInput());
      if (transient) {
        await srcMap.release();
      }
      this.exportBuf = await RedactionRenderer.encodeJpeg(rendered);
      await rendered.release();
      this.exportReady = true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'prepareExport failed: %{public}s', JSON.stringify(e));
      this.exportStatus = '渲染失败,请重试';
    }
  }

  private async saveToAlbum(result: SaveButtonOnClickResult): Promise<void> {
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      this.getUIContext().getPromptAction().showToast({ message: '未获得保存授权' });
      return;
    }
    if (this.exportBuf === null) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg');
      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, this.exportBuf);
      fs.closeSync(file);
      this.showExport = false;
      this.getUIContext().getPromptAction().showToast({ message: '已保存副本到相册(不含元数据)' });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '保存失败,请重试' });
    }
  }

  private async shareImage(): Promise<void> {
    if (this.exportBuf === null) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path = context.filesDir + '/dama_share.jpg';
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this.exportBuf);
      fs.closeSync(file);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.IMAGE,
        uri: fileUri.getUriFromPath(path),
        title: '打码图片'
      };
      const data = new systemShare.SharedData(record);
      const controller = new systemShare.ShareController(data);
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'share failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
    }
  }
}
