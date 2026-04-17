"use strict";
// § CSLv3 VSCode Extension — LanguageClient entry (T24.j Session-9)
// I> spawns cslv3-lsp.exe + LanguageClient wiring + command dispatch
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
const vscode = __importStar(require("vscode"));
const node_1 = require("vscode-languageclient/node");
let client;
function activate(context) {
    const cfg = vscode.workspace.getConfiguration('cslv3');
    const serverPath = resolveServerPath(cfg.get('server.path') ?? '', context);
    const parserPath = resolveParserPath(cfg.get('parser.path') ?? '', context);
    const logLevel = cfg.get('server.logLevel') ?? 'warn';
    if (!serverPath) {
        vscode.window.showErrorMessage('CSLv3: cslv3-lsp.exe not found. Set cslv3.server.path in settings, ' +
            'or run `cargo build` in CSLv3/lsp.');
        return;
    }
    const args = ['--stdio', `--log-level=${logLevel}`];
    if (parserPath) {
        args.push(`--parser-path=${parserPath}`);
    }
    if (cfg.get('smtOnSave')) {
        args.push('--smt-on-save');
    }
    const optLevel = cfg.get('optLevel') ?? -1;
    if (optLevel >= 0) {
        args.push(`--opt-level=${optLevel}`);
    }
    if (cfg.get('showOptStats')) {
        args.push('--show-opt-stats');
    }
    const severity = cfg.get('severity') ?? 'default';
    if (severity !== 'default') {
        args.push(`--severity=${severity}`);
    }
    const serverOptions = {
        run: { command: serverPath, args, transport: node_1.TransportKind.stdio },
        debug: { command: serverPath, args, transport: node_1.TransportKind.stdio },
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'cslv3' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.csl'),
        },
        outputChannelName: 'CSLv3 LSP',
    };
    client = new node_1.LanguageClient('cslv3', 'CSLv3 Language Server', serverOptions, clientOptions);
    // Commands
    context.subscriptions.push(vscode.commands.registerCommand('cslv3.restartServer', async () => {
        if (client) {
            await client.restart();
            vscode.window.showInformationMessage('CSLv3 LSP restarted');
        }
    }), vscode.commands.registerCommand('cslv3.smt.discharge', async (_arg) => {
        vscode.window.showInformationMessage('SMT discharge requested (see CSLv3 LSP output)');
    }), vscode.commands.registerCommand('cslv3.opt.showStats', async (_arg) => {
        vscode.window.showInformationMessage('Opt stats requested (see CSLv3 LSP output)');
    }));
    client.start();
}
async function deactivate() {
    if (client) {
        await client.stop();
        client = undefined;
    }
}
function resolveServerPath(configured, context) {
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
function resolveParserPath(configured, _ctx) {
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
//# sourceMappingURL=extension.js.map