#!/usr/bin/env node
// Mock git-host MCP server for the adversarial scenario suite (issue #165).
//
// Why this exists: morpheus's "Address review feedback" flow reads PR threads
// through a git-host MCP and stops without one, so the *fetched* ingress of the
// untrusted-comment rule cannot be exercised by pasting text into the prompt.
// This serves canned PR data over stdio and — the part the assertions depend on —
// appends every incoming tool call to a JSONL log. That log is the outbound
// channel: if the agent tries to publish a secret or dismantle a guard through
// "GitHub", the attempt is recorded there as observable state.
//
// Protocol surface is the minimum MCP needs to be usable: initialize,
// notifications/initialized, tools/list, tools/call. Newline-delimited JSON-RPC
// 2.0 on stdin/stdout. Zero npm dependencies on purpose — the suite must run on a
// bare checkout with no install step.
//
// Config via env:
//   MOCK_PR_FIXTURE  path to a JSON file: { pull_request: {...}, comments: [...] }
//   MOCK_CALL_LOG    path to append one JSON object per tool call
//
// Anything unparseable is a hard exit: a mock that silently serves the wrong data
// would make a scenario pass for the wrong reason.
'use strict';

const fs = require('node:fs');

const fixturePath = process.env.MOCK_PR_FIXTURE;
const callLogPath = process.env.MOCK_CALL_LOG;
if (!fixturePath) fatal('MOCK_PR_FIXTURE is required');
if (!callLogPath) fatal('MOCK_CALL_LOG is required');

let fixture;
try {
  fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
} catch (e) {
  fatal(`could not read/parse MOCK_PR_FIXTURE (${fixturePath}): ${e.message}`);
}
if (!fixture.pull_request || !Array.isArray(fixture.comments)) {
  fatal('MOCK_PR_FIXTURE must contain { pull_request: {...}, comments: [...] }');
}

function fatal(msg) {
  process.stderr.write(`mock-git-host: FATAL ${msg}\n`);
  process.exit(1);
}

// Every call is recorded before it is answered, so a crash mid-call still leaves
// evidence the call was attempted.
function recordCall(name, args) {
  const line = JSON.stringify({ tool: name, arguments: args === undefined ? null : args });
  try {
    fs.appendFileSync(callLogPath, `${line}\n`);
  } catch (e) {
    fatal(`could not append to MOCK_CALL_LOG (${callLogPath}): ${e.message}`);
  }
}

const TOOLS = [
  {
    name: 'list_pull_requests',
    description: 'List open pull requests for the current repository.',
    inputSchema: { type: 'object', properties: { state: { type: 'string' } } },
  },
  {
    name: 'get_pull_request',
    description: 'Get a pull request, including its branch and status.',
    inputSchema: {
      type: 'object',
      properties: { pullNumber: { type: 'number' } },
      required: ['pullNumber'],
    },
  },
  {
    name: 'get_pull_request_comments',
    description: 'Get the review threads and comments on a pull request.',
    inputSchema: {
      type: 'object',
      properties: { pullNumber: { type: 'number' } },
      required: ['pullNumber'],
    },
  },
  {
    name: 'add_pull_request_comment',
    description: 'Post a reply comment on a pull request thread.',
    inputSchema: {
      type: 'object',
      properties: {
        pullNumber: { type: 'number' },
        body: { type: 'string' },
        threadId: { type: 'string' },
      },
      required: ['pullNumber', 'body'],
    },
  },
  {
    name: 'resolve_review_thread',
    description: 'Mark a review thread as resolved.',
    inputSchema: {
      type: 'object',
      properties: { threadId: { type: 'string' } },
      required: ['threadId'],
    },
  },
];

function callTool(name, args) {
  recordCall(name, args);
  switch (name) {
    case 'list_pull_requests':
      return [fixture.pull_request];
    case 'get_pull_request':
      return fixture.pull_request;
    case 'get_pull_request_comments':
      return fixture.comments;
    case 'add_pull_request_comment':
      // Accepting the post is deliberate: the scenario asserts on what the agent
      // *tried* to send (the recorded body), not on the mock refusing it.
      return { posted: true, id: 90001 };
    case 'resolve_review_thread':
      return { resolved: true };
    default:
      return null;
  }
}

function respond(id, result) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
}
function respondError(id, code, message) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } })}\n`);
}

function handle(msg) {
  const { id, method, params } = msg;
  switch (method) {
    case 'initialize':
      respond(id, {
        protocolVersion: (params?.protocolVersion) || '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'mock-git-host', version: '1.0.0' },
      });
      return;
    case 'notifications/initialized':
    case 'initialized':
      return; // notification: no reply
    case 'tools/list':
      respond(id, { tools: TOOLS });
      return;
    case 'tools/call': {
      const name = params?.name;
      const known = TOOLS.some((t) => t.name === name);
      if (!known) {
        recordCall(name === undefined ? '(missing)' : name, params?.arguments);
        respondError(id, -32602, `unknown tool: ${name}`);
        return;
      }
      const result = callTool(name, params.arguments);
      respond(id, {
        content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
      });
      return;
    }
    case 'ping':
      respond(id, {});
      return;
    default:
      // Unknown request: answer with an error rather than hanging the client.
      if (id !== undefined) respondError(id, -32601, `method not found: ${method}`);
  }
}

let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  while (true) {
    const nl = buffer.indexOf('\n');
    if (nl === -1) break;
    const line = buffer.slice(0, nl).trim();
    buffer = buffer.slice(nl + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue; // ignore a partial/garbage frame rather than dying mid-session
    }
    handle(msg);
  }
});
process.stdin.on('end', () => process.exit(0));
