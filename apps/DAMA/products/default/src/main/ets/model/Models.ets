/**
 * Models.ets — DAMA (打码) 核心数据模型。
 * 与 iOS 版 Models.swift 对应:归一化坐标(左上原点,0..1)。
 */

export enum RiskType {
  FACE = 'face',
  CODE = 'code',
  EMAIL = 'email',
  PHONE = 'phone',
  ADDRESS = 'address',
  URL = 'url',
  PAYMENT = 'payment',
  NAME = 'name',
  ID_NUMBER = 'idNumber',
  ORDER_NUMBER = 'orderNumber',
  LICENSE_PLATE = 'licensePlateCandidate',
  OTHER_TEXT = 'otherText'
}

export enum RiskLevel {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2
}

export enum RedactionStyle {
  BLOCK = 'block',
  PIXELATE = 'pixelate',
  BLUR = 'blur'
}

export function riskTypeName(t: RiskType): string {
  switch (t) {
    case RiskType.FACE:
      return '人脸';
    case RiskType.CODE:
      return '二维码 / 条码';
    case RiskType.EMAIL:
      return '邮箱';
    case RiskType.PHONE:
      return '电话';
    case RiskType.ADDRESS:
      return '地址';
    case RiskType.URL:
      return '链接';
    case RiskType.PAYMENT:
      return '卡号';
    case RiskType.NAME:
      return '姓名';
    case RiskType.ID_NUMBER:
      return '证件号';
    case RiskType.ORDER_NUMBER:
      return '订单 / 快递单号';
    case RiskType.LICENSE_PLATE:
      return '车牌';
    case RiskType.OTHER_TEXT:
      return '手动区域';
    default:
      return '其他';
  }
}

export function riskLevelName(l: RiskLevel): string {
  switch (l) {
    case RiskLevel.HIGH:
      return '高';
    case RiskLevel.MEDIUM:
      return '中';
    default:
      return '疑似';
  }
}

/** 归一化矩形,左上原点,分量 0..1。 */
export class NRect {
  x: number = 0;
  y: number = 0;
  w: number = 0;
  h: number = 0;

  constructor(x: number, y: number, w: number, h: number) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  get maxX(): number {
    return this.x + this.w;
  }

  get maxY(): number {
    return this.y + this.h;
  }

  get midX(): number {
    return this.x + this.w / 2;
  }

  get midY(): number {
    return this.y + this.h / 2;
  }

  contains(px: number, py: number): boolean {
    return px >= this.x && px <= this.maxX && py >= this.y && py <= this.maxY;
  }

  area(): number {
    return this.w * this.h;
  }

  clone(): NRect {
    return new NRect(this.x, this.y, this.w, this.h);
  }

  static iou(a: NRect, b: NRect): number {
    const ix = Math.max(a.x, b.x);
    const iy = Math.max(a.y, b.y);
    const ax = Math.min(a.maxX, b.maxX);
    const ay = Math.min(a.maxY, b.maxY);
    if (ax <= ix || ay <= iy) {
      return 0;
    }
    const inter = (ax - ix) * (ay - iy);
    const union = a.area() + b.area() - inter;
    return union <= 0 ? 0 : inter / union;
  }

  static union(a: NRect, b: NRect): NRect {
    const x = Math.min(a.x, b.x);
    const y = Math.min(a.y, b.y);
    const mx = Math.max(a.maxX, b.maxX);
    const my = Math.max(a.maxY, b.maxY);
    return new NRect(x, y, mx - x, my - y);
  }
}

let nextRegionId = 1;

/** 一个建议或手动的打码区域。 */
export class RiskRegion {
  id: number;
  type: RiskType;
  box: NRect;
  confidence: number;
  detectedText: string;
  level: RiskLevel;
  selected: boolean;
  manual: boolean;
  /** 人脸用表情覆盖(替代填充样式);空串表示不用表情。 */
  emoji: string;

  constructor(type: RiskType, box: NRect, level: RiskLevel, detectedText: string = '',
    confidence: number = 1, manual: boolean = false, emoji: string = '') {
    this.id = nextRegionId++;
    this.type = type;
    this.box = box;
    this.confidence = confidence;
    this.detectedText = detectedText;
    this.level = level;
    // 低置信度(疑似)默认不勾选,与 iOS PRD §8.3 一致。
    this.selected = level > RiskLevel.LOW;
    this.manual = manual;
    this.emoji = emoji;
  }

  clone(): RiskRegion {
    const r = new RiskRegion(this.type, this.box.clone(), this.level, this.detectedText,
      this.confidence, this.manual, this.emoji);
    r.selected = this.selected;
    // clone 保留 id,便于撤销栈按 id 恢复选中状态。
    r.id = this.id;
    return r;
  }
}

/** 涂鸦笔迹,点坐标与线宽均归一化(线宽相对图宽)。 */
export class Stroke {
  points: number[] = []; // [x0,y0,x1,y1,...]
  width: number = 0.02;
  color: string = '#000000';

  constructor(width: number, color: string) {
    this.width = width;
    this.color = color;
  }

  clone(): Stroke {
    const s = new Stroke(this.width, this.color);
    s.points = this.points.slice();
    return s;
  }
}

/** OCR 单词(归一化框)。 */
export class OcrWord {
  text: string;
  rect: NRect;

  constructor(text: string, rect: NRect) {
    this.text = text;
    this.rect = rect;
  }
}

/** OCR 行:整行框 + 文本 + 词框。支撑"文字大爆炸"逐词打码。 */
export class OcrLine {
  text: string;
  rect: NRect;
  words: OcrWord[];

  constructor(text: string, rect: NRect, words: OcrWord[]) {
    this.text = text;
    this.rect = rect;
    this.words = words;
  }
}
