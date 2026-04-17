// § CSLv3 LSP — Backend (tower-lsp LanguageServer trait-impl) (T24.b Session-9)
// I> Full lifecycle + didOpen/Change/Save/Close + 12+ feature methods
// I> async throughout ; parser.exe subprocess via spawn_blocking in shim
// I> per-URI document cache + background-parse task via tokio::spawn

use crate::{
    code_actions, completion, config::Config, diagnostics, formatting, goto, hover, opt_diag,
    parser_shim::ParserShim, semantic_tokens, smt_diag, workspace_index::WorkspaceIndex,
};
use dashmap::DashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer};

/// Per-URI state cache.
#[derive(Debug, Clone)]
pub struct Document {
    #[allow(dead_code)] pub uri:  Url,
    pub text: String,
    #[allow(dead_code)] pub version: i32,
}

pub struct Backend {
    pub client:   Client,
    pub cfg:      RwLock<Config>,
    pub docs:     DashMap<Url, Document>,
    pub shim:     ParserShim,
    pub index:    Arc<WorkspaceIndex>,
}

impl Backend {
    pub fn new(client: Client, cfg: Config) -> Self {
        let shim = ParserShim::new(cfg.parser_path.clone());
        let index = Arc::new(WorkspaceIndex::new_in_memory());
        Self {
            client,
            cfg: RwLock::new(cfg),
            docs: DashMap::new(),
            shim,
            index,
        }
    }

    async fn publish_for(&self, uri: Url) {
        let text = match self.docs.get(&uri) {
            Some(d) => d.text.clone(),
            None => return,
        };
        let cfg = self.cfg.read().await.clone();

        // Parse/cssllint is the fast primary diagnostic source.
        let mut merged: Vec<Vec<Diagnostic>> = Vec::new();
        match self.shim.cssllint(uri.as_str(), &text).await {
            Ok(j) => merged.push(diagnostics::diagnostics_from_cssllint(&j, &uri)),
            Err(e) => {
                tracing::warn!("cssllint error for {}: {:#}", uri, e);
            }
        }
        // Typecheck is usually fast enough to run inline.
        if let Ok(j) = self.shim.typecheck(uri.as_str(), &text).await {
            merged.push(diagnostics::diagnostics_from_cssllint(&j, &uri));
        }
        // SMT on save only (configurable).
        if cfg.smt_on_save {
            if let Ok(j) = self
                .shim
                .smt(uri.as_str(), &text, &cfg.z3_path, &cfg.cvc5_path)
                .await
            {
                merged.push(diagnostics::diagnostics_from_smt(&j, &uri));
            }
        }
        // Optional opt-stats as info diagnostics.
        if cfg.show_opt_stats && cfg.opt_level >= 0 {
            if let Ok(j) = self.shim.opt_stats(uri.as_str(), &text, cfg.opt_level).await {
                merged.push(opt_diag::diagnostics_from_opt_stats(&j, &uri));
            }
        }

        let list = diagnostics::merge(merged);
        self.client
            .publish_diagnostics(uri.clone(), list, None)
            .await;
    }
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, p: InitializeParams) -> Result<InitializeResult> {
        tracing::info!("initialize : root={:?}", p.root_uri);

        let caps = ServerCapabilities {
            text_document_sync: Some(TextDocumentSyncCapability::Options(
                TextDocumentSyncOptions {
                    open_close: Some(true),
                    change: Some(TextDocumentSyncKind::FULL),
                    save: Some(TextDocumentSyncSaveOptions::Supported(true)),
                    ..Default::default()
                },
            )),
            hover_provider: Some(HoverProviderCapability::Simple(true)),
            completion_provider: Some(CompletionOptions {
                trigger_characters: Some(vec![
                    "'".to_string(),
                    "§".to_string(),
                    ".".to_string(),
                    "⊗".to_string(),
                    "@".to_string(),
                    "+".to_string(),
                    ":".to_string(),
                ]),
                resolve_provider: Some(false),
                ..Default::default()
            }),
            definition_provider: Some(OneOf::Left(true)),
            references_provider: Some(OneOf::Left(true)),
            document_symbol_provider: Some(OneOf::Left(true)),
            workspace_symbol_provider: Some(OneOf::Left(true)),
            document_formatting_provider: Some(OneOf::Left(true)),
            document_range_formatting_provider: Some(OneOf::Left(true)),
            code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
            code_lens_provider: Some(CodeLensOptions {
                resolve_provider: Some(false),
            }),
            semantic_tokens_provider: Some(
                SemanticTokensServerCapabilities::SemanticTokensOptions(SemanticTokensOptions {
                    work_done_progress_options: Default::default(),
                    legend: SemanticTokensLegend {
                        token_types: semantic_tokens::TOKEN_TYPES.iter().map(|s| SemanticTokenType::new(s)).collect(),
                        token_modifiers: vec![],
                    },
                    range: Some(false),
                    full: Some(SemanticTokensFullOptions::Bool(true)),
                }),
            ),
            ..Default::default()
        };

        Ok(InitializeResult {
            server_info: Some(ServerInfo {
                name: "cslv3-lsp".to_string(),
                version: Some(env!("CARGO_PKG_VERSION").to_string()),
            }),
            capabilities: caps,
        })
    }

    async fn initialized(&self, _: InitializedParams) {
        self.client
            .log_message(MessageType::INFO, "cslv3-lsp initialized")
            .await;
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_open(&self, p: DidOpenTextDocumentParams) {
        let uri = p.text_document.uri.clone();
        self.docs.insert(
            uri.clone(),
            Document {
                uri: uri.clone(),
                text: p.text_document.text,
                version: p.text_document.version,
            },
        );
        self.publish_for(uri).await;
    }

    async fn did_change(&self, p: DidChangeTextDocumentParams) {
        let uri = p.text_document.uri.clone();
        // FULL sync ⇒ single content_changes entry
        if let Some(change) = p.content_changes.into_iter().next() {
            self.shim.invalidate_uri(uri.as_str());
            self.docs.insert(
                uri.clone(),
                Document {
                    uri: uri.clone(),
                    text: change.text,
                    version: p.text_document.version,
                },
            );
        }
        // Debounce via tokio::time::sleep inside spawned task.
        let debounce = self.cfg.read().await.debounce_ms;
        let cloned_uri = uri.clone();
        let docs = self.docs.clone();
        let shim = self.shim.clone();
        let client = self.client.clone();
        let cfg = self.cfg.read().await.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(debounce)).await;
            let text = match docs.get(&cloned_uri) {
                Some(d) => d.text.clone(),
                None => return,
            };
            let mut merged: Vec<Vec<Diagnostic>> = Vec::new();
            if let Ok(j) = shim.cssllint(cloned_uri.as_str(), &text).await {
                merged.push(diagnostics::diagnostics_from_cssllint(&j, &cloned_uri));
            }
            if let Ok(j) = shim.typecheck(cloned_uri.as_str(), &text).await {
                merged.push(diagnostics::diagnostics_from_cssllint(&j, &cloned_uri));
            }
            if cfg.show_opt_stats && cfg.opt_level >= 0 {
                if let Ok(j) = shim.opt_stats(cloned_uri.as_str(), &text, cfg.opt_level).await {
                    merged.push(opt_diag::diagnostics_from_opt_stats(&j, &cloned_uri));
                }
            }
            let list = diagnostics::merge(merged);
            client.publish_diagnostics(cloned_uri, list, None).await;
        });
    }

    async fn did_save(&self, p: DidSaveTextDocumentParams) {
        let uri = p.text_document.uri.clone();
        self.publish_for(uri).await;
    }

    async fn did_close(&self, p: DidCloseTextDocumentParams) {
        self.docs.remove(&p.text_document.uri);
    }

    async fn hover(&self, p: HoverParams) -> Result<Option<Hover>> {
        let uri = p.text_document_position_params.text_document.uri;
        let pos = p.text_document_position_params.position;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(hover::hover_at(&self.shim, uri.as_str(), &text, pos).await)
    }

    async fn completion(&self, p: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = p.text_document_position.text_document.uri;
        let pos = p.text_document_position.position;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(Some(CompletionResponse::Array(completion::complete_at(
            &text,
            pos,
            p.context.as_ref(),
        ))))
    }

    async fn formatting(&self, p: DocumentFormattingParams) -> Result<Option<Vec<TextEdit>>> {
        let uri = p.text_document.uri;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(formatting::format_document(&self.shim, &text).await)
    }

    async fn range_formatting(
        &self,
        p: DocumentRangeFormattingParams,
    ) -> Result<Option<Vec<TextEdit>>> {
        let uri = p.text_document.uri;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(formatting::format_range(&self.shim, &text, p.range).await)
    }

    async fn goto_definition(
        &self,
        p: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        let uri = p.text_document_position_params.text_document.uri;
        let pos = p.text_document_position_params.position;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(goto::definition_at(&self.shim, &self.index, &uri, &text, pos).await)
    }

    async fn references(&self, p: ReferenceParams) -> Result<Option<Vec<Location>>> {
        let uri = p.text_document_position.text_document.uri;
        let pos = p.text_document_position.position;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(goto::references_at(&self.shim, &self.index, &uri, &text, pos).await)
    }

    async fn document_symbol(
        &self,
        p: DocumentSymbolParams,
    ) -> Result<Option<DocumentSymbolResponse>> {
        let uri = p.text_document.uri;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(Some(DocumentSymbolResponse::Nested(
            goto::document_symbols(&self.shim, &text).await,
        )))
    }

    async fn symbol(
        &self,
        p: WorkspaceSymbolParams,
    ) -> Result<Option<Vec<SymbolInformation>>> {
        Ok(Some(self.index.workspace_symbols(&p.query)))
    }

    async fn code_action(&self, p: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        let actions = code_actions::actions_for(&p);
        if actions.is_empty() {
            return Ok(None);
        }
        Ok(Some(actions))
    }

    async fn code_lens(&self, p: CodeLensParams) -> Result<Option<Vec<CodeLens>>> {
        let uri = p.text_document.uri;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        let cfg = self.cfg.read().await.clone();
        Ok(Some(smt_diag::code_lenses(&self.shim, uri, text, &cfg).await))
    }

    async fn semantic_tokens_full(
        &self,
        p: SemanticTokensParams,
    ) -> Result<Option<SemanticTokensResult>> {
        let uri = p.text_document.uri;
        let Some(doc) = self.docs.get(&uri) else { return Ok(None) };
        let text = doc.text.clone();
        drop(doc);
        Ok(Some(SemanticTokensResult::Tokens(
            semantic_tokens::tokens_for(&text),
        )))
    }

    async fn did_change_configuration(&self, p: DidChangeConfigurationParams) {
        let mut cfg = self.cfg.write().await;
        if let Some(obj) = p.settings.as_object() {
            if let Some(smt) = obj.get("smtOnSave").and_then(|v| v.as_bool()) {
                cfg.smt_on_save = smt;
            }
            if let Some(opt) = obj.get("optLevel").and_then(|v| v.as_i64()) {
                cfg.opt_level = opt as i32;
            }
            if let Some(stats) = obj.get("showOptStats").and_then(|v| v.as_bool()) {
                cfg.show_opt_stats = stats;
            }
        }
    }

    async fn did_change_watched_files(&self, _: DidChangeWatchedFilesParams) {
        // trigger re-index ; stubbed for now
    }
}
