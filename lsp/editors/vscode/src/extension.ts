// § CSLv3 VSCode Extension — LanguageClient entry (T24.j Session-9)
// I> spawns cslv3-lsp.exe + LanguageClient wiring + command dispatch

import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export function activate(context: vscode.ExtensionContext) {
  const cfg = vscode.workspace.getConfiguration('cslv3');
  const serverPath = resolveServerPath(cfg.get<string>('server.path') ?? '', context);
  const parserPath = resolveParserPath(cfg.get<string>('parser.path') ?? '', context);
  const logLevel = cfg.get<string>('server.logLevel') ?? 'warn';

  if (!serverPath) {
    vscode.window.showErrorMessage(
      'CSLv3: cslv3-lsp.exe not found. Set cslv3.server.path in settings, ' +
      'or run `cargo build` in CSLv3/lsp.'
    );
    return;
  }

  const args: string[] = ['--stdio', `--log-level=${logLevel}`];
  if (parserPath) {
    args.push(`--parser-path=${parserPath}`);
  }
  if (cfg.get<boolean>('smtOnSave')) {
    args.push('--smt-on-save');
  }
  const optLevel = cfg.get<number>('optLevel') ?? -1;
  if (optLevel >= 0) {
    args.push(`--opt-level=${optLevel}`);
  }
  if (cfg.get<boolean>('showOptStats')) {
    args.push('--show-opt-stats');
  }
  const severity = cfg.get<string>('severity') ?? 'default';
  if (severity !== 'default') {
    args.push(`--severity=${severity}`);
  }

  const serverOptions: ServerOptions = {
    run: { command: serverPath, args, transport: TransportKind.stdio },
    debug: { command: serverPath, args, transport: TransportKind.stdio },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'cslv3' }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.csl'),
    },
    outputChannelName: 'CSLv3 LSP',
  };

  client = new LanguageClient(
    'cslv3',
    'CSLv3 Language Server',
    serverOptions,
    clientOptions,
  );

  // Commands
  context.subscriptions.push(
    vscode.commands.registerCommand('cslv3.restartServer', async () => {
      if (client) {
        await client.restart();
        vscode.window.showInformationMessage('CSLv3 LSP restarted');
      }
    }),
    vscode.commands.registerCommand('cslv3.smt.discharge', async (_arg) => {
      vscode.window.showInformationMessage('SMT discharge requested (see CSLv3 LSP output)');
    }),
    vscode.commands.registerCommand('cslv3.opt.showStats', async (_arg) => {
      vscode.window.showInformationMessage('Opt stats requested (see CSLv3 LSP output)');
    }),
  );

  client.start();
}

export async function deactivate(): Promise<void> {
  if (client) {
    await client.stop();
    client = undefined;
  }
}

function resolveServerPath(configured: string, context: vscode.ExtensionContext): string {
  if (configured && fs.existsSync(configured)) {
    return configured;
  }
  // Candidates : repo-root cargo target, extension-bundled bin
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '';
  const candidates = [
    path.join(workspaceRoot, 'lsp', 'target', 'release', 'cslv3-lsp.exe'),
    path.join(workspaceRoot, 'lsp', 'target', 'debug', 'cslv3-lsp.exe'),
    path.join(workspaceRoot, 'lsp', 'target', 'release', 'cslv3-lsp'),
    path.join(workspaceRoot, 'lsp', 'target', 'debug', 'cslv3-lsp'),
    path.join(context.extensionPath, 'bin', 'cslv3-lsp.exe'),
    path.join(context.extensionPath, 'bin', 'cslv3-lsp'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return '';
}

function resolveParserPath(configured: string, _ctx: vscode.ExtensionContext): string {
  if (configured && fs.existsSync(configured)) {
    return configured;
  }
  const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '';
  const candidates = [
    path.join(workspaceRoot, 'parser.exe'),
    path.join(workspaceRoot, '..', 'parser.exe'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return '';
}
