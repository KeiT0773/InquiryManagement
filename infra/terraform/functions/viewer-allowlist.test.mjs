// viewer-allowlist.js の単体テスト。Terraform と同じく %%ALLOWED_PREFIXES%% を置き換えてから読み込む。
//   node --test infra/terraform/functions/viewer-allowlist.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

function loadHandler(prefixes) {
  const source = readFileSync(new URL('./viewer-allowlist.js', import.meta.url), 'utf8')
    .replace('%%ALLOWED_PREFIXES%%', JSON.stringify(prefixes));
  return new Function(`${source}\nreturn handler;`)();
}

// CloudFront が渡す event の最小限の形
function eventFrom(ip) {
  return { viewer: { ip }, request: { method: 'GET', uri: '/index.html', headers: {} } };
}

const handler = loadHandler(['240d:1a:9e6:8c00::/64']);
// 通過したときは要求（statusCode を持たない）がそのまま返る
const allowed = (ip) => handler(eventFrom(ip)).statusCode === undefined;

test('許可したネットワーク内の IPv6 は通過する（要求をそのまま返す）', () => {
  const event = eventFrom('240d:1a:9e6:8c00:c420:62fa:51ce:c4af');
  assert.equal(handler(event), event.request);
});

test('後半（インターフェース ID）が変わっても通過する', () => {
  assert.ok(allowed('240d:1a:9e6:8c00:1:2:3:4'));
  assert.ok(allowed('240d:1a:9e6:8c00::1')); // :: で省略した形
  assert.ok(allowed('240D:001A:09E6:8C00:0000:0000:0000:0001')); // 大文字・先頭の 0 あり
});

test('ネットワーク番号が 1 つでも違う IPv6 は 403', () => {
  for (const ip of ['240d:1a:9e6:8c01::1', '240d:1a:9e6:8b00::1', '2001:db8::1', '::1']) {
    const res = handler(eventFrom(ip));
    assert.equal(res.statusCode, 403, ip);
    assert.match(res.body.data, /アクセスできません/);
  }
});

test('IPv4 は自宅のアドレスでも 403', () => {
  for (const ip of ['207.65.168.137', '10.0.0.1', '::ffff:207.65.168.137']) {
    assert.equal(handler(eventFrom(ip)).statusCode, 403, ip);
  }
});

test('不正な値は 403', () => {
  for (const ip of ['', 'not-an-ip', '1::2::3', '1:2:3:4:5:6:7:8:9', undefined]) {
    assert.equal(handler(eventFrom(ip)).statusCode, 403, String(ip));
  }
});

test('/56 や複数のネットワークも判定できる', () => {
  const multi = loadHandler(['2001:db8:1200::/56', '240d:1a:9e6:8c00::/64']);
  assert.equal(multi(eventFrom('2001:db8:12ff::1')).statusCode, 403); // 先頭 56 ビットが違う
  assert.notEqual(multi(eventFrom('2001:db8:1200:ff::1')).statusCode, 403); // /56 の範囲内
  assert.notEqual(multi(eventFrom('240d:1a:9e6:8c00::9')).statusCode, 403);
});

test('許可リストが空なら、すべて 403', () => {
  const none = loadHandler([]);
  assert.equal(none(eventFrom('240d:1a:9e6:8c00::1')).statusCode, 403);
});
