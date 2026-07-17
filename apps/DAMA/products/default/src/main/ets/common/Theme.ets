/**
 * Theme.ets — 主题常量(绿色主题,与 iOS 版 brandGreen 一致)。
 */

export class Theme {
  static readonly GREEN = '#3BC76E';
  static readonly GREEN_DIM = 'rgba(59, 199, 110, 0.20)';
  static readonly INK = '#1A1C1A';
  static readonly INK_SECONDARY = '#6B716C';
  static readonly BG = '#FFFFFF';
  static readonly CARD = '#F4F7F5';
  static readonly SEPARATOR = '#E3E8E4';
  static readonly DANGER = '#E7392F';
  static readonly EDITOR_BG = '#17191B';

  /** 色块 / 涂鸦可选色板。 */
  static readonly SWATCHES: string[] =
    ['#000000', '#FFFFFF', '#3BC76E', '#E7392F', '#2D6CDF', '#F5B400', '#8B5CF6', '#FF7A59'];

  /** 人脸表情可选集。 */
  static readonly EMOJIS: string[] =
    ['😀', '😎', '🙂', '😷', '🥸', '🐶', '🐱', '🌟', '❤️', '🙈', '🤖', '🌸'];
}
