// アクセス元の制限（CloudFront Functions、runtime: cloudfront-js-2.0）。インフラ設計書 6.4（タスク管理アプリから流用）。
//
// CloudFront が利用者からの要求を受け取った直後（viewer-request）に動き、
// アクセス元の IP アドレスが許可した IPv6 のネットワーク番号に含まれなければ、403 を返す。
// IPv4 は他の契約者と共有されていることがあるため、すべて拒否する。
//
// 下の ALLOWED_PREFIXES の右辺（% で囲んだ目印）は、Terraform（cloudfront.tf）が変数
// allowed_viewer_ipv6_prefixes の値（例：["240d:1a:9e6:8c00::/64"]）に置き換えてから CloudFront に登録する。
// 単体テスト：node --test infra/terraform/functions/viewer-allowlist.test.mjs

var ALLOWED_PREFIXES = %%ALLOWED_PREFIXES%%;

// IPv6 アドレスの文字列を、16 ビットずつの数 8 つに展開する。IPv6 として読めなければ null。
//   "240d:1a:9e6:8c00::1" → [0x240d, 0x1a, 0x9e6, 0x8c00, 0, 0, 0, 1]
function parseIpv6(text) {
  if (typeof text !== 'string' || text.indexOf(':') === -1) {
    return null; // IPv4（または不正な値）
  }
  var halves = text.split('::');
  if (halves.length > 2) {
    return null;
  }
  var head = halves[0] === '' ? [] : halves[0].split(':');
  var tail = halves.length === 2 && halves[1] !== '' ? halves[1].split(':') : [];
  var zeros = 8 - head.length - tail.length;
  if (halves.length === 1 ? zeros !== 0 : zeros < 1) {
    return null;
  }
  var parts = head.slice();
  for (var z = 0; z < (halves.length === 2 ? zeros : 0); z++) {
    parts.push('0');
  }
  parts = parts.concat(tail);

  var words = [];
  for (var i = 0; i < 8; i++) {
    if (!/^[0-9a-fA-F]{1,4}$/.test(parts[i])) {
      return null; // 末尾が IPv4 の形（::ffff:1.2.3.4）なども、ここで不可にする
    }
    words.push(parseInt(parts[i], 16));
  }
  return words;
}

// "240d:1a:9e6:8c00::/64" を { words: [...], length: 64 } にする
function parsePrefix(cidr) {
  var slash = cidr.indexOf('/');
  return { words: parseIpv6(cidr.substring(0, slash)), length: parseInt(cidr.substring(slash + 1), 10) };
}

// アドレスの先頭 prefix.length ビットが、ネットワーク番号と一致するか
function inPrefix(words, prefix) {
  for (var i = 0; i < 8; i++) {
    var bits = Math.min(16, prefix.length - i * 16);
    if (bits <= 0) {
      return true;
    }
    var mask = (0xffff << (16 - bits)) & 0xffff;
    if ((words[i] & mask) !== (prefix.words[i] & mask)) {
      return false;
    }
  }
  return true;
}

function handler(event) {
  var words = parseIpv6(event.viewer.ip);
  if (words !== null) {
    for (var i = 0; i < ALLOWED_PREFIXES.length; i++) {
      if (inPrefix(words, parsePrefix(ALLOWED_PREFIXES[i]))) {
        return event.request; // 許可：そのまま EC2（nginx）へ転送する
      }
    }
  }
  return {
    statusCode: 403,
    statusDescription: 'Forbidden',
    headers: {
      'content-type': { value: 'text/plain; charset=utf-8' },
      'cache-control': { value: 'no-store' },
    },
    body: {
      encoding: 'text',
      data: '403 このネットワークからはアクセスできません（自宅のネットワークからだけ利用できます）。\n',
    },
  };
}
