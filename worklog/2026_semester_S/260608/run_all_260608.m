function run_all_260608(opts)
%====================================================================
% 260608 全自動ドライバ（席を立つ用）
%
%   これ1本で:
%     1) 方向1：ゲイン掃引テスト  frfr_phase2_gainsweep_260608_v1
%     2) 方向2：モデルベースFB    frfr_phase2_model_260608_v1
%     3) 各ログを自動解析         analyze_log_260608（図3枚＋サマリCSV）
%   を順に実行し、最後に「勝ち筋（終端std最小区間）」をまとめて表示する。
%
%   各ステップは try/catch で囲み、片方が失敗しても残りを続行。
%   実験スクリプトは onCleanup で ao0=0V・DAQ/VISA解放まで自動で行う。
%
%   ※ 録音(WAV)解析 analyze_jitter_260608 は offset_s（録音開始時刻差）が
%     手入力なので自動化に含めない。戻ってきてから手動で実行する。
%
%   使い方（Current Folder を 260608 に。これだけ貼って席を立つ）:
%     run_all_260608();
%   動作確認（各区間60s に短縮して全工程を素早く通す）:
%     o.slot_s = 60;  run_all_260608(o);
%
%   opts（既定）: slot_s([]=各スクリプト既定の180) を両実験へ渡す
%====================================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    eo = struct();                          % 実験スクリプトへ渡すopts
    if isfield(opts,'slot_s') && ~isempty(opts.slot_s), eo.slot_s = opts.slot_s; end

    t0 = datetime('now');
    fprintf('\n############ 260608 全自動ラン 開始 %s ############\n', ...
        datestr(t0,'yyyy-mm-dd HH:MM:SS'));

    R1 = [];  R2 = [];

    %% === 1) 方向1：ゲイン掃引 =========================================
    fprintf('\n========== [1/3] ゲイン掃引テスト ==========\n');
    try
        R1 = frfr_phase2_gainsweep_260608_v1(eo);
    catch ME
        warning('ゲイン掃引でエラー: %s', ME.message);
    end

    %% === 2) 方向2：モデルベースFB =====================================
    fprintf('\n========== [2/3] モデルベースFB ==========\n');
    try
        R2 = frfr_phase2_model_260608_v1(eo);
    catch ME
        warning('モデルFBでエラー: %s', ME.message);
    end

    %% === 3) ログ自動解析（ハード不要）================================
    fprintf('\n========== [3/3] ログ自動解析 ==========\n');
    A1 = [];  A2 = [];
    if ~isempty(R1) && isfield(R1,'log_csv')
        try, A1 = analyze_log_260608(R1.log_csv); catch ME, warning('R1解析エラー: %s', ME.message); end
    end
    if ~isempty(R2) && isfield(R2,'log_csv')
        try, A2 = analyze_log_260608(R2.log_csv); catch ME, warning('R2解析エラー: %s', ME.message); end
    end

    %% === 最終まとめ ===================================================
    fprintf('\n############ 全自動ラン 完了 ############\n');
    fprintf('所要: %.1f 分\n', minutes(datetime('now') - t0));
    fprintf('\n----- 結論（終端std最小＝勝ち筋）-----\n');
    report_best('方向1 ゲイン掃引', A1);
    report_best('方向2 モデルFB',   A2);
    fprintf('\n図・CSVはこのフォルダに自動保存済み（*_segstd.png が主結果）。\n');
    fprintf('録音を録っていれば、戻ってから手動で:\n');
    if ~isempty(R1), fprintf('  analyze_jitter_260608("録音.wav", "%s", offset_s);\n', R1.segmap_csv); end
    if ~isempty(R2), fprintf('  analyze_jitter_260608("録音.wav", "%s", offset_s);\n', R2.segmap_csv); end
end

%% === ヘルパー: 解析結果から勝ち筋を表示 ==============================
function report_best(label, A)
    if isempty(A) || ~isfield(A,'std_terminal_ns')
        fprintf('%-16s : (解析結果なし)\n', label);
        return;
    end
    [bs, bi] = min(A.std_terminal_ns);
    seg = A.segment{bi};
    % HOLD基準
    ih = find(strcmpi(A.mode,'HOLD'), 1);
    if ~isempty(ih)
        fprintf('%-16s : 最小=%-6s std=%.3f ns | HOLD基準=%.3f ns\n', ...
            label, seg, bs, A.std_terminal_ns(ih));
    else
        fprintf('%-16s : 最小=%-6s std=%.3f ns\n', label, seg, bs);
    end
end
