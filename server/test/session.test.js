'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const session = require('../src/session');

const KEY = 'panel-password';

function fakeRes() {
  return {
    headers: {},
    setHeader(name, value) {
      this.headers[name] = value;
    },
  };
}

test('sign/verify roundtrip returns the expiry', () => {
  const exp = Date.now() + 60_000;
  const token = session.sign(exp, KEY);
  assert.equal(typeof token, 'string');
  assert.ok(token.includes('.'));
  assert.equal(session.verify(token, KEY), exp);
});

test('verify rejects a different key material', () => {
  const token = session.sign(Date.now() + 60_000, KEY);
  assert.equal(session.verify(token, 'other-password'), 0);
});

test('verify rejects expired tokens', () => {
  const token = session.sign(Date.now() - 1_000, KEY);
  assert.equal(session.verify(token, KEY), 0);
});

test('verify rejects malformed tokens', () => {
  assert.equal(session.verify('', KEY), 0);
  assert.equal(session.verify('no-dot-here', KEY), 0);
  assert.equal(session.verify(null, KEY), 0);
  assert.equal(session.verify(undefined, KEY), 0);
  assert.equal(session.verify(42, KEY), 0);
  assert.equal(session.verify('.only-sig', KEY), 0);
  // Valid signature over a body that is not a number.
  assert.equal(session.verify(session.sign('not-a-number', KEY), KEY), 0);
});

test('sessionFromReq reads the panel cookie only', () => {
  const exp = Date.now() + 60_000;
  const token = session.sign(exp, KEY);

  const req = { headers: { cookie: `foo=bar; ${session.COOKIE}=${token}; baz=1` } };
  assert.equal(session.sessionFromReq(req, KEY), exp);

  assert.equal(session.sessionFromReq({ headers: {} }, KEY), 0);
  assert.equal(session.sessionFromReq({ headers: { cookie: 'foo=bar' } }, KEY), 0);
  assert.equal(session.sessionFromReq({ headers: { cookie: `${session.COOKIE}=garbage` } }, KEY), 0);
  assert.equal(session.sessionFromReq({ headers: { cookie: `${session.COOKIE}=` } }, KEY), 0);
});

test('setCookie writes a verifiable HttpOnly cookie', () => {
  const exp = Date.now() + 60_000;
  const res = fakeRes();
  session.setCookie(res, exp, { keyMaterial: KEY });

  const raw = res.headers['Set-Cookie'];
  assert.match(raw, new RegExp(`^${session.COOKIE}=`));
  assert.match(raw, /Path=\//);
  assert.match(raw, /HttpOnly/);
  assert.match(raw, /SameSite=Lax/);
  assert.match(raw, /Max-Age=(59|60)/);
  assert.ok(!/;\s*Secure/.test(raw));

  const token = raw.slice(`${session.COOKIE}=`.length).split(';')[0];
  assert.equal(session.verify(token, KEY), exp);
});

test('setCookie adds Secure when requested', () => {
  const res = fakeRes();
  session.setCookie(res, Date.now() + 60_000, { secure: true, keyMaterial: KEY });
  assert.match(res.headers['Set-Cookie'], /Secure/);
});

test('clearCookie expires immediately', () => {
  const res = fakeRes();
  session.clearCookie(res);
  const raw = res.headers['Set-Cookie'];
  assert.match(raw, new RegExp(`^${session.COOKIE}=`));
  assert.match(raw, /Max-Age=0/);
});

test('timingSafeEqualStr compares by hash, not length', () => {
  assert.equal(session.timingSafeEqualStr('secret', 'secret'), true);
  assert.equal(session.timingSafeEqualStr('secret', 'secreT'), false);
  assert.equal(session.timingSafeEqualStr('', ''), true);
  assert.equal(session.timingSafeEqualStr('a'.repeat(500), 'a'.repeat(500)), true);
});
