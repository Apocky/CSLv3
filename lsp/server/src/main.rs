// § CSLv3 LSP SERVER — entry point (T24 Session-9)
// I> tokio-runtime + tower-lsp trait-impl ; stdio transport for VSCode-compat
// I> CLI flags : --stdio (default) | --tcp=<addr> | --log-level=<lvl>
//               --parser-path=<path> | --version

use anyhow::Result;
use std::env;

mod code_actions;
mod completion;
mod config;
mod diagnostics;
mod formatting;
mod goto;
mod hover;
mod opt_diag;
mod parser_shim;
mod semantic_tokens;
mod server;
mod smt_diag;
mod workspace_index;

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();

    // --version / --help early-exit
    for a in &args[1..] {
        if a == "--version" || a == "-V" {
            println!("cslv3-lsp {}", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        if a == "--help" || a == "-h" {
            print_usage();
            return Ok(());
        }
    }

    // Logging : default WARN ; override via --log-level=<lvl>
    let log_level = parse_log_level(&args).unwrap_or_else(|| "warn".to_string());
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(&log_level)),
        )
        .with_writer(std::io::stderr)
        .init();

    // parse CLI config
    let cfg = config::parse_cli(&args);
    tracing::info!("cslv3-lsp starting ; transport={:?}", cfg.transport);

    let (service, socket) = tower_lsp::LspService::build(|client| {
        server::Backend::new(client, cfg.clone())
    })
    .finish();

    match cfg.transport {
        config::Transport::Stdio => {
            let stdin = tokio::io::stdin();
            let stdout = tokio::io::stdout();
            tower_lsp::Server::new(stdin, stdout, socket)
                .serve(service)
                .await;
        }
        config::Transport::Tcp(ref addr) => {
            use tokio::net::TcpListener;
            let listener = TcpListener::bind(addr.as_str()).await?;
            tracing::info!("listening tcp {}", addr);
            loop {
                let (socket_stream, _) = listener.accept().await?;
                let (read, write) = tokio::io::split(socket_stream);
                let (service, lsp_socket) =
                    tower_lsp::LspService::build(|client| server::Backend::new(client, cfg.clone()))
                        .finish();
                tokio::spawn(async move {
                    tower_lsp::Server::new(read, write, lsp_socket)
                        .serve(service)
                        .await;
                });
            }
        }
    }

    Ok(())
}

fn parse_log_level(args: &[String]) -> Option<String> {
    for a in args {
        if let Some(rest) = a.strip_prefix("--log-level=") {
            return Some(rest.to_string());
        }
    }
    None
}

fn print_usage() {
    println!(
        r#"cslv3-lsp — CSLv3 Language Server (v3.17 subset)

USAGE:
  cslv3-lsp [OPTIONS]

OPTIONS:
  --stdio                (default) VSCode-compatible stdio transport
  --tcp=<host:port>      TCP transport ; useful for debugging
  --log-level=<lvl>      trace|debug|info|warn|error  (default: warn)
  --parser-path=<path>   override parser.exe location
                         (default: searches PATH + ./parser.exe)
  --version              print version and exit
  --help                 print this help and exit

Consumes parser.exe for all truth-source operations (cssllint + --ir +
--smt + --opt). Requires parser.exe on PATH or passed via --parser-path."#
    );
}
