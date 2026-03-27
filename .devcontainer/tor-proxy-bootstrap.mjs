/**
 * tor-proxy-bootstrap.mjs
 *
 * Node.js preload module that routes ALL outbound traffic through Tor.
 * Usage: node --import ./tor-proxy-bootstrap.mjs shannon.mjs ...
 *
 * Covers:
 *  1. Native fetch() — via undici global SOCKS5 dispatcher (custom connector)
 *  2. node-fetch     — via patched http/https.request with socks-proxy-agent
 *  3. axios          — via HTTPS_PROXY / HTTP_PROXY env vars
 *  4. OpenAI SDK     — respects proxy env vars through its http client
 *  5. CLI tools      — env vars propagated to child_process
 *  6. Playwright     — handled by wrapper script via launch args
 */

import { Agent, setGlobalDispatcher } from 'undici';
import { SocksClient } from 'socks';
import { SocksProxyAgent } from 'socks-proxy-agent';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';

const TOR_HOST = '127.0.0.1';
const TOR_PORT = 9050;
const TOR_SOCKS = `socks5h://${TOR_HOST}:${TOR_PORT}`;

// ── User-Agent rotation (avoid Cloudflare bot detection) ──
const USER_AGENTS = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0',
  'Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0',
];
function randomUA() { return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)]; }
globalThis.__randomUA = randomUA;

// ── 1. Route native fetch() through Tor via undici custom SOCKS5 connector ──
function socksConnector(options, callback) {
  const port = Number(options.port) || (options.protocol === 'https:' ? 443 : 80);
  SocksClient.createConnection({
    proxy: { host: TOR_HOST, port: TOR_PORT, type: 5 },
    command: 'connect',
    destination: { host: options.hostname, port },
  }).then(({ socket }) => {
    if (options.protocol === 'https:') {
      const tlsSocket = tls.connect({
        socket,
        servername: options.servername || options.hostname,
        ALPNProtocols: ['http/1.1'],
      });
      tlsSocket.on('secureConnect', () => callback(null, tlsSocket));
      tlsSocket.on('error', (err) => callback(err, null));
    } else {
      callback(null, socket);
    }
  }).catch((err) => callback(err, null));
}

const torDispatcher = new Agent({ connect: socksConnector });
setGlobalDispatcher(torDispatcher);

// ── 1b. Wrap globalThis.fetch to inject User-Agent header ──
const _origFetch = globalThis.fetch;
globalThis.fetch = function fetchWithUA(input, init = {}) {
  init.headers = new Headers(init.headers || {});
  if (!init.headers.has('User-Agent')) {
    init.headers.set('User-Agent', randomUA());
  }
  return _origFetch.call(this, input, init);
};

// ── 2. Set env vars for axios, CLI tools, and SDKs ──
process.env.HTTP_PROXY  = TOR_SOCKS;
process.env.HTTPS_PROXY = TOR_SOCKS;
process.env.ALL_PROXY   = TOR_SOCKS;
process.env.http_proxy  = TOR_SOCKS;
process.env.https_proxy = TOR_SOCKS;
process.env.all_proxy   = TOR_SOCKS;

// ── 3. Provide a global SocksProxyAgent for libraries that need an http.Agent ──
const torHttpAgent = new SocksProxyAgent(TOR_SOCKS);
globalThis.__torAgent = torHttpAgent;

// ── 4. Monkey-patch http/https.request and .get for node-fetch and others ──
//
// Node signatures:
//   request(url, cb)           → args = [string, function]
//   request(url, opts, cb)     → args = [string, object, function]
//   request(opts, cb)          → args = [object, function]
//
// When args[0] is a URL string and args[1] is the callback (function),
// we must INSERT an options object, not overwrite the callback.
function injectAgent(args, agent) {
  // Inject both Tor agent and User-Agent header
  function addUA(opts) {
    if (!opts.headers) opts.headers = {};
    if (!opts.headers['User-Agent'] && !opts.headers['user-agent']) {
      opts.headers['User-Agent'] = randomUA();
    }
  }

  if (typeof args[0] === 'string' || args[0] instanceof URL) {
    if (typeof args[1] === 'function') {
      // (url, cb) → (url, {agent, headers}, cb)
      const opts = { agent };
      addUA(opts);
      args.splice(1, 0, opts);
    } else if (typeof args[1] === 'object' && args[1] !== null) {
      if (!args[1].agent) args[1].agent = agent;
      addUA(args[1]);
    }
  } else if (typeof args[0] === 'object' && args[0] !== null) {
    if (!args[0].agent) args[0].agent = agent;
    addUA(args[0]);
  }
  return args;
}

function patchModule(mod, agent) {
  const origRequest = mod.request;
  const origGet = mod.get;

  mod.request = function patchedRequest(...args) {
    return origRequest.apply(this, injectAgent(args, agent));
  };

  mod.get = function patchedGet(...args) {
    return origGet.apply(this, injectAgent(args, agent));
  };
}

patchModule(http, torHttpAgent);
patchModule(https, torHttpAgent);

console.log('[TOR] All network traffic routed through Tor (socks5h://127.0.0.1:9050)');
