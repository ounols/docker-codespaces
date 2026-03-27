/**
 * tor-tool-runner-patch.mjs
 *
 * Patches shannon-uncontained's tool-runner.js at runtime to inject
 * Tor proxy flags into all CLI security tools.
 *
 * Applied by the setup script after npm install.
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const SHANNON_DIR = join(process.env.HOME || '/home/kali', 'shannon-uncontained');
const TOOL_RUNNER = join(SHANNON_DIR, 'src/local-source-generator/v2/tools/runners/tool-runner.js');

if (!existsSync(TOOL_RUNNER)) {
  console.error('[TOR-PATCH] tool-runner.js not found at:', TOOL_RUNNER);
  process.exit(1);
}

let content = readFileSync(TOOL_RUNNER, 'utf-8');

// Skip if already patched
if (content.includes('__TOR_PROXY_PATCHED__')) {
  console.log('[TOR-PATCH] tool-runner.js already patched, skipping.');
  process.exit(0);
}

// Inject proxy flag mapper right before the runTool export or function
const PROXY_INJECT = `
// __TOR_PROXY_PATCHED__
const TOR_PROXY = 'socks5://127.0.0.1:9050';
const TOR_PROXY_H = 'socks5h://127.0.0.1:9050';

const UA_LIST = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:133.0) Gecko/20100101 Firefox/133.0',
  'Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0',
];
function randomUA() { return UA_LIST[Math.floor(Math.random() * UA_LIST.length)]; }

function injectTorProxy(command) {
  const ua = randomUA();
  // nmap: sudo + --proxies socks4:// (raw socket requires root)
  if (/\\bnmap\\b/.test(command) && !command.includes('--proxies')) {
    command = command.replace(/\\bnmap\\b/, 'sudo nmap --proxies socks4://127.0.0.1:9050');
  }
  // nuclei: -proxy + -H User-Agent
  if (/\\bnuclei\\b/.test(command) && !command.includes('-proxy')) {
    command = command.replace(/\\bnuclei\\b/, \`nuclei -proxy \${TOR_PROXY} -H "User-Agent: \${ua}"\`);
  }
  // subfinder: -proxy
  if (/\\bsubfinder\\b/.test(command) && !command.includes('-proxy')) {
    command = command.replace(/\\bsubfinder\\b/, \`subfinder -proxy \${TOR_PROXY_H}\`);
  }
  // katana: -proxy + -H User-Agent
  if (/\\bkatana\\b/.test(command) && !command.includes('-proxy')) {
    command = command.replace(/\\bkatana\\b/, \`katana -proxy \${TOR_PROXY} -H "User-Agent: \${ua}"\`);
  }
  // httpx: -proxy + -H User-Agent
  if (/\\bhttpx\\b/.test(command) && !command.includes('-proxy')) {
    command = command.replace(/\\bhttpx\\b/, \`httpx -proxy \${TOR_PROXY} -H "User-Agent: \${ua}"\`);
  }
  // sqlmap: --proxy + --random-agent
  if (/\\bsqlmap\\b/.test(command) && !command.includes('--proxy')) {
    command = command.replace(/\\bsqlmap\\b/, \`sqlmap --proxy=\${TOR_PROXY} --random-agent\`);
  }
  // feroxbuster: --proxy + -A User-Agent
  if (/\\bferoxbuster\\b/.test(command) && !command.includes('--proxy')) {
    command = command.replace(/\\bferoxbuster\\b/, \`feroxbuster --proxy \${TOR_PROXY} -A "\${ua}"\`);
  }
  // ffuf: -x (proxy) + -H User-Agent
  if (/\\bffuf\\b/.test(command) && !command.includes(' -x ')) {
    command = command.replace(/\\bffuf\\b/, \`ffuf -x \${TOR_PROXY} -H "User-Agent: \${ua}"\`);
  }
  // gau: uses env vars (ALL_PROXY already set by bootstrap)
  // nikto: -useproxy + -useragent
  if (/\\bnikto\\b/.test(command) && !command.includes('-useproxy')) {
    command = command.replace(/\\bnikto\\b/, \`nikto -useproxy \${TOR_PROXY_H} -useragent "\${ua}"\`);
  }
  // whatweb: --proxy + -U User-Agent
  if (/\\bwhatweb\\b/.test(command) && !command.includes('--proxy')) {
    command = command.replace(/\\bwhatweb\\b/, \`whatweb --proxy \${TOR_PROXY_H} -U "\${ua}"\`);
  }
  // commix: --proxy + --random-agent
  if (/\\bcommix\\b/.test(command) && !command.includes('--proxy')) {
    command = command.replace(/\\bcommix\\b/, \`commix --proxy=\${TOR_PROXY_H} --random-agent\`);
  }
  // curl: -A User-Agent
  if (/\\bcurl\\b/.test(command) && !command.includes(' -A ') && !command.includes('--user-agent')) {
    command = command.replace(/\\bcurl\\b/, \`curl -A "\${ua}"\`);
  }
  return command;
}

`;

// Find the runTool function and inject the proxy mapper
if (content.includes('export async function runTool')) {
  // Insert proxy code before the export
  content = content.replace(
    'export async function runTool',
    PROXY_INJECT + '\nexport async function runTool'
  );
  // Inject the call inside runTool to transform the command
  content = content.replace(
    /const\s*{\s*stdout\s*,\s*stderr\s*}\s*=\s*await\s+execAsync\s*\(\s*command/,
    'command = injectTorProxy(command);\n    const { stdout, stderr } = await execAsync(command'
  );
} else if (content.includes('export function runTool')) {
  content = content.replace(
    'export function runTool',
    PROXY_INJECT + '\nexport function runTool'
  );
  content = content.replace(
    /const\s*{\s*stdout\s*,\s*stderr\s*}\s*=\s*await\s+execAsync\s*\(\s*command/,
    'command = injectTorProxy(command);\n    const { stdout, stderr } = await execAsync(command'
  );
}

writeFileSync(TOOL_RUNNER, content, 'utf-8');
console.log('[TOR-PATCH] tool-runner.js patched to inject Tor proxy flags for all CLI tools.');
