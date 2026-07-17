/**
 * TextRuleMatcher.ets — 第二检测层:对 OCR 文本做纯正则规则匹配。
 * 从 iOS 版 TextRuleMatcher.swift 移植;差异:JS 正则不支持 (?i:) 内联组,
 * 姓名规则拆成「标签(忽略大小写)→ 值(区分大小写、需首字母大写)」两步。
 */

import { RiskType, RiskLevel } from '../model/Models';

export class RuleMatch {
  start: number;
  end: number;
  type: RiskType;
  level: RiskLevel;
  /** 为真时覆盖整个 OCR 行(如地址)。 */
  wholeLine: boolean;

  constructor(start: number, end: number, type: RiskType, level: RiskLevel, wholeLine: boolean = false) {
    this.start = start;
    this.end = end;
    this.type = type;
    this.level = level;
    this.wholeLine = wholeLine;
  }
}

const emailRe = new RegExp('[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}', 'gi');

const urlRe = new RegExp(
  '(?:https?://|www\\.)[^\\s<>"\']+|\\b[a-z0-9][a-z0-9-]*(?:\\.[a-z0-9-]+)*\\.(?:com|net|org|io|co|app|dev|me|info|biz|ly|us|uk|de|fr|es|it|pt|br|mx|ar|cl|ca|eu|edu|gov)\\b(?:/[^\\s<>"\']*)?',
  'gi');

/** 13–19 位数字(可含空格/连字符),再做 Luhn 校验。 */
const paymentRe = new RegExp('(?<!\\d)(?:\\d[ \\-]?){12,18}\\d(?!\\d)', 'g');

/** 电话候选,匹配后再按位数过滤。 */
const phoneRe = new RegExp(
  '(?<![\\d/.])(?:\\+\\d{1,3}[ .\\-]?)?(?:\\(\\d{1,4}\\)[ .\\-]?)?\\d(?:[ .\\-]?\\d){5,12}(?!\\d)', 'g');

/** UPS 风格快递单号。 */
const carrierRe = new RegExp('\\b1Z[0-9A-Z]{16}\\b', 'g');

/** 美国社保号 NNN-NN-NNNN(必须带连字符)。 */
const ssnRe = new RegExp('(?<!\\d)\\d{3}-\\d{2}-\\d{4}(?!\\d)', 'g');

/** 关键词锚定的证件号(护照/身份证/驾照/税号/NINO…),捕获组 1 = 号码。 */
const idRe = new RegExp(
  "\\b(?:passport|national\\s*id|identity(?:\\s*(?:card|no\\.?|number))?|id\\s*(?:card|no\\.?|number)|driver'?s?\\s+licen[cs]e|dl\\s*no\\.?|licen[cs]e\\s*(?:no\\.?|number)|ssn|social\\s*security(?:\\s*(?:no\\.?|number))?|tax\\s*id|national\\s*insurance|nino)(?:\\s*(?:no\\.?|number|id|#|:|：))*\\s+([A-Z0-9][A-Z0-9\\-]{4,18})", 'gi');

/** 姓名标签(忽略大小写)——值用 nameValueSticky 从标签结尾处区分大小写地续匹配。 */
const nameLabelRe = new RegExp(
  '\\b(?:name|full\\s*name|billed\\s+to|bill\\s+to|cardholder|card\\s*holder|account\\s+holder|customer|recipient|patient|attention|attn|dear|mr|mrs|ms|dr)\\b[:.\\s#]{1,3}', 'gi');
const nameValueSticky = new RegExp("[A-Z][a-zA-Z'.\\-]+(?:\\s+[A-Z][a-zA-Z'.\\-]+){0,3}", 'y');

/** 关键词锚定的订单/快递号,捕获组 1 = 编码。 */
const orderRe = new RegExp(
  '\\b(?:order|tracking|track|ref(?:erence)?|invoice|shipment|pedido|rastreio|seguimiento|commande|bestellung|ordine)(?:\\s*(?:no\\.?|number|id|#|:|：))*\\s+([A-Z0-9][A-Z0-9\\-]{5,24})', 'gi');

/** 车牌候选(区分大小写)。 */
const plateRe = new RegExp('\\b[A-Z]{1,3}[ \\-]?\\d{1,4}[ \\-]?[A-Z0-9]{0,3}\\b', 'g');

/** 各上线地区语言的地址关键词。 */
const addressRe = new RegExp(
  '\\b(?:street|avenue|ave|boulevard|blvd|road|lane|drive|apartment|apt|suite|zip ?code|zip|postcode|postal code|p\\.?o\\.? box|calle|avenida|colonia|c[oó]digo postal|rua|bairro|cep|rue|code postal|\\w*stra(?:ss|ß)e|\\w*str\\.|platz|plz|via|piazza|cap)\\b', 'i');

/** 短后缀(St/Rd/Dr/Ln)仅在紧跟大写词后才算地址标记。 */
const addressSuffixRe = new RegExp('\\b[A-Z][a-z]+ (?:St|Rd|Dr|Ln)\\.?\\b');

// —— 中国大陆规则 ——

/** 身份证号:18 位 = 6 位区划 + 8 位出生日期(校验)+ 3 位顺序 + 1 位校验。 */
const chinaIDRe = new RegExp(
  '(?<!\\d)\\d{6}(?:18|19|20)\\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])\\d{3}[\\dXx](?![\\dXx])', 'g');

/** 带标签的中文姓名:「姓名:张三」「收件人 李四」。捕获组 1 = 2–4 字姓名。 */
const chineseNameRe = new RegExp(
  '(?:姓名|收件人|收货人|客户|持卡人|联系人|户名|开户名|检测人|受理人|经办人|负责人|报修人)[:：\\s]*([\\u4e00-\\u9fff]{2,4})', 'g');

/** 关键词锚定的中文订单/服务号,捕获组 1 = 编码。 */
const chineseOrderRe = new RegExp(
  '(?:订单号|服务单号|受理单号|工单号|流水号|快递单号|物流单号|单号|编号)[:：\\s]*([A-Za-z0-9][A-Za-z0-9\\-]{5,24})', 'g');

/**
 * 卡片安全码(CVV/CVC/安全码)后跟 3–4 位数字。
 * 注意:JS 的 \b 不把 CJK 当词字符(ICU 会),中文关键词不能包在 \b 里。
 */
const cvvRe = new RegExp('(?:\\b(?:cvv2?|cvc2?|cid)\\b|安全码|校验码)[:.：\\s#]{0,3}(\\d{3,4})(?!\\d)', 'gi');

/** 中文地址标记(CJK 无词边界,任意位置匹配)。 */
const chineseAddressRe = new RegExp(
  '省|市|区|县|镇|乡|村|路|街|巷|弄|号|栋|幢|单元|室|楼|大厦|花园|小区|广场|邮编|邮政编码');

/** 大陆车牌:省份简称 + 城市字母 + 5–6 位(新能源 6 位)。低置信度。 */
const chinesePlateRe = new RegExp(
  '[京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼][A-Z][A-Z0-9]{5,6}(?![A-Z0-9])', 'g');

/** 场景提示关键词(命中后中风险升高)。 */
const contextKeywordRe = new RegExp(
  '\\b(?:order|tracking|address|phone|tel|email|ship(?:ping)? to|deliver(?:y)? to)\\b', 'i');

const nameLabelLineRe = new RegExp(
  '^\\s*(?:card\\s*holder|cardholder|account\\s*holder|full\\s*name|name|recipient|customer|attention|attn|收件人|收货人|姓名|客户|持卡人|联系人|户名|开户名|检测人|受理人|经办人|负责人|报修人)\\s*[:：]?\\s*$', 'i');
const nameValueLineRe = new RegExp(
  "^\\s*(?:[\\u4e00-\\u9fff]{2,4}|[A-Z][a-zA-Z'.\\-]+(?:\\s+[A-Z][a-zA-Z'.\\-]+){0,3})\\s*$");
const cvvLabelLineRe = new RegExp('^\\s*(?:cvv2?|cvc2?|cid|安全码|校验码)\\s*[:：]?\\s*$', 'i');
const cvvValueLineRe = new RegExp('^\\s*\\d{3,4}\\s*$');

function execAll(re: RegExp, s: string): RegExpExecArray[] {
  const out: RegExpExecArray[] = [];
  re.lastIndex = 0;
  let m = re.exec(s);
  while (m !== null) {
    out.push(m);
    if (m[0].length === 0) {
      re.lastIndex += 1;
    }
    m = re.exec(s);
  }
  return out;
}

function countDigits(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 48 && c <= 57) {
      n++;
    }
  }
  return n;
}

function countLetters(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charAt(i);
    if (c.toLowerCase() !== c.toUpperCase()) {
      n++;
    }
  }
  return n;
}

function hasDigit(s: string): boolean {
  return countDigits(s) > 0;
}

/** 捕获组 1 在整串中的起始位置(从 match 起点向后找)。 */
function groupStart(m: RegExpExecArray, group: number): number {
  const idx = m[0].indexOf(m[group]);
  return (m.index === undefined ? 0 : m.index) + (idx < 0 ? 0 : idx);
}

export class TextRuleMatcher {
  /**
   * 返回一行 OCR 文本中的敏感匹配。
   * 重叠时优先级:邮箱 > 链接 > 卡号 > 单号 > 证件 > 姓名 > 电话 > 车牌。
   * 地址按整行级别独立上报。
   */
  static matches(line: string, sceneHint: boolean = false): RuleMatch[] {
    if (line.length === 0) {
      return [];
    }
    const taken: number[] = []; // [start,end, start,end, ...]
    const results: RuleMatch[] = [];

    const overlapsTaken = (s: number, e: number): boolean => {
      for (let i = 0; i < taken.length; i += 2) {
        if (s < taken[i + 1] && e > taken[i]) {
          return true;
        }
      }
      return false;
    };
    const claim = (s: number, e: number, type: RiskType, level: RiskLevel): void => {
      if (e <= s || overlapsTaken(s, e)) {
        return;
      }
      taken.push(s);
      taken.push(e);
      results.push(new RuleMatch(s, e, type, level));
    };
    const boost = (level: RiskLevel): RiskLevel => {
      return sceneHint && level === RiskLevel.MEDIUM ? RiskLevel.HIGH : level;
    };

    // 1. 邮箱
    for (const m of execAll(emailRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.EMAIL, RiskLevel.HIGH);
    }

    // 2. 链接
    for (const m of execAll(urlRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.URL, boost(RiskLevel.MEDIUM));
    }

    // 3. 卡号(Luhn 校验)+ 安全码
    for (const m of execAll(paymentRe, line)) {
      const digits = m[0].replace(new RegExp('[^0-9]', 'g'), '');
      if (digits.length < 13 || digits.length > 19 || !TextRuleMatcher.passesLuhn(digits)) {
        continue;
      }
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.PAYMENT, RiskLevel.HIGH);
    }
    for (const m of execAll(cvvRe, line)) {
      if (m.length > 1 && m[1] !== undefined) {
        const s = groupStart(m, 1);
        claim(s, s + m[1].length, RiskType.PAYMENT, RiskLevel.HIGH);
      }
    }

    // 4. 订单 / 快递单号
    for (const m of execAll(carrierRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.ORDER_NUMBER, boost(RiskLevel.MEDIUM));
    }
    for (const m of execAll(orderRe, line)) {
      if (m.length > 1 && m[1] !== undefined && hasDigit(m[1])) {
        const s = groupStart(m, 1);
        claim(s, s + m[1].length, RiskType.ORDER_NUMBER, boost(RiskLevel.MEDIUM));
      }
    }
    for (const m of execAll(chineseOrderRe, line)) {
      if (m.length > 1 && m[1] !== undefined) {
        const s = groupStart(m, 1);
        claim(s, s + m[1].length, RiskType.ORDER_NUMBER, boost(RiskLevel.MEDIUM));
      }
    }

    // 4.5 证件号。SSN 先于电话认领,避免 9 位数字被电话规则吞掉。
    for (const m of execAll(ssnRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.ID_NUMBER, RiskLevel.HIGH);
    }
    for (const m of execAll(idRe, line)) {
      if (m.length > 1 && m[1] !== undefined && hasDigit(m[1])) {
        const s = groupStart(m, 1);
        claim(s, s + m[1].length, RiskType.ID_NUMBER, RiskLevel.HIGH);
      }
    }
    for (const m of execAll(chinaIDRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.ID_NUMBER, RiskLevel.HIGH);
    }

    // 4.6 带标签的姓名(「Billed to: Jane Roe」/「姓名:张三」)
    for (const m of execAll(nameLabelRe, line)) {
      const at = (m.index ?? 0) + m[0].length;
      nameValueSticky.lastIndex = at;
      const v = nameValueSticky.exec(line);
      if (v !== null) {
        claim(at, at + v[0].length, RiskType.NAME, RiskLevel.MEDIUM);
      }
    }
    for (const m of execAll(chineseNameRe, line)) {
      if (m.length > 1 && m[1] !== undefined) {
        const s = groupStart(m, 1);
        claim(s, s + m[1].length, RiskType.NAME, RiskLevel.MEDIUM);
      }
    }

    // 5. 电话
    for (const m of execAll(phoneRe, line)) {
      const digits = countDigits(m[0]);
      if (digits < 7 || digits > 15) {
        continue;
      }
      const uniq = new Set<string>();
      for (let i = 0; i < m[0].length; i++) {
        const ch = m[0].charAt(i);
        if (ch >= '0' && ch <= '9') {
          uniq.add(ch);
        }
      }
      if (uniq.size <= 1) {
        continue;
      }
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.PHONE, RiskLevel.HIGH);
    }

    // 6. 车牌候选(始终低置信度 →「疑似」)
    for (const m of execAll(plateRe, line)) {
      const letters = countLetters(m[0]);
      const digits = countDigits(m[0]);
      const alnum = letters + digits;
      if (alnum < 5 || alnum > 8 || letters < 2 || digits < 2) {
        continue;
      }
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.LICENSE_PLATE, RiskLevel.LOW);
    }
    for (const m of execAll(chinesePlateRe, line)) {
      const s = m.index ?? 0;
      claim(s, s + m[0].length, RiskType.LICENSE_PLATE, RiskLevel.LOW);
    }

    // 7. 地址:命中关键词且行内有数字或逗号 → 整行
    const hasKeyword = addressRe.test(line) || addressSuffixRe.test(line) || chineseAddressRe.test(line);
    if (hasKeyword && (hasDigit(line) || line.indexOf(',') >= 0 || line.indexOf('，') >= 0)) {
      results.push(new RuleMatch(0, line.length, RiskType.ADDRESS, boost(RiskLevel.MEDIUM), true));
    }

    return results;
  }

  /** 该行是否只是姓名字段标签(表单常将标签与值分行)。 */
  static isNameLabelLine(line: string): boolean {
    return nameLabelLineRe.test(line);
  }

  /** 该行是否像一个裸姓名:2–4 个汉字,或 1–4 个首字母大写/全大写拉丁词。 */
  static looksLikeName(line: string): boolean {
    return nameValueLineRe.test(line);
  }

  /** 该行是否只是安全码标签(CVV / CVC / 安全码)。 */
  static isCVVLabel(line: string): boolean {
    return cvvLabelLineRe.test(line);
  }

  /** 该行是否只是 3–4 位裸数字(配对的 CVV/CVC 值)。 */
  static looksLikeCVV(line: string): boolean {
    return cvvValueLineRe.test(line);
  }

  /** 场景提示:任意 OCR 行是否包含上下文关键词。 */
  static containsContextKeywords(lines: string[]): boolean {
    for (const line of lines) {
      if (contextKeywordRe.test(line)) {
        return true;
      }
    }
    return false;
  }

  static passesLuhn(digits: string): boolean {
    let sum = 0;
    for (let i = 0; i < digits.length; i++) {
      const d = digits.charCodeAt(digits.length - 1 - i) - 48;
      if (d < 0 || d > 9) {
        return false;
      }
      if (i % 2 === 1) {
        const doubled = d * 2;
        sum += doubled > 9 ? doubled - 9 : doubled;
      } else {
        sum += d;
      }
    }
    return sum % 10 === 0;
  }
}
