function result = sim_frfr_model_260610_v0(meas_csv, opts)
%====================================================================
% Phase 2 N/400モデルFB ── 決定論クローズドループ・シミュレーション（260610 v0）
%
%  狙い（先の議論の選択肢(a)）:
%   ハードウェア無し（DAQ/VISA 不要）の純オフライン解析で、
%   モデルFB制御則による「制御電圧 u」と「位相差 FRFR φ」の時間変化を
%   決定論的にシミュレートし、実測 260610 ランに重ね描きして検証する。
%
%  プラントモデル（連続）:
%     dφ/dt = Δf,   Δf = K·(u − u0)
%       φ  : 位相差 FRFR [ns]
%       u  : 制御電圧 [V]
%       Δf : 周波数差 [ns/s]
%       K  ≈ 860 ns/(V·s)（260605 最小ステップ応答の実測値）
%       u0 : Δf=0 となる動作点電圧 [V]
%  離散（Ts=1 s, 前進オイラー）:
%     φ[k+1] = φ[k] + Ts·K·(u[k] − u0)
%  LSB 表現（実コードと等価）:
%     df = g_LSB·N,  g_LSB ≈ K·lsb_V,  1LSB = lsb_V = 20/2^16 ≈ 305 µV
%
%  制御則は frfr_model_260610_v1.m の実コードを localcontrol() として
%  そのまま移植（round() による量子化デッドバンド込み）。
%
%  ▼ 機能 ▼
%   1) 実測CSVが無ければ自己完結デモ（Kp_e=[0.02 0.04 0.08]+HOLD を合成）
%   2) プラント同定: 実測 df vs ao0 の線形回帰で K_hat, u0_hat を推定（→ K≈860 検証）
%   3) クローズドループ・シム: 実測の区間（segment / kpe / mode）スケジュールを
%      そのまま再生し、φ_sim を実測初期値から前進。各ステップで φ_sim を
%      「FRFR」として制御則に通し u_next を求め、プラントで φ を1歩進める。
%   4) 重ね描き図: (i) FRFR vs t, (ii) 電圧 vs t, (iii) K 回帰
%   5) コンソール要約: K_hat vs 860, u0_hat, 区間別 RMS 差、決定論シムの乖離注記
%
%  使い方（Current Folder を 260610 に）:
%    R = sim_frfr_model_260610_v0();                    % デモ（CSV無し）
%    R = sim_frfr_model_260610_v0("frfr_model_YYYYmmdd_HHMMSS.csv");
%    o.use_nominal_K = true; R = sim_frfr_model_260610_v0(csv, o); % K=860固定
%
%  opts（既定）: g_LSB(0.26) df_max(1.5) dN_max(4) df_ema(0.5) Ts(1.0)
%               u_init(1.54) FRFR_ref(25) dac_range_V(20) dac_bits(16)
%               K_nominal(860) u0_nominal(1.54) use_nominal_K(false)
%               save_tag('') demo_seg_len(120)
%
%  ※ 本スクリプトは純オフライン解析。daq/visadev/outputSingleScan/onCleanup は
%    一切使用しない（CLAUDE.md 規約準拠）。
%====================================================================

    %% === 引数・opts =====================================================
    if nargin < 1, meas_csv = ''; end
    if nargin < 2 || isempty(opts), opts = struct(); end
    def = struct('g_LSB',0.26, 'df_max',1.5, 'dN_max',4, 'df_ema',0.5, 'Ts',1.0, ...
                 'u_init',1.54, 'FRFR_ref',25, 'dac_range_V',20, 'dac_bits',16, ...
                 'K_nominal',860, 'u0_nominal',1.54, 'use_nominal_K',false, ...
                 'save_tag','', 'demo_seg_len',120);
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    Ts    = opts.Ts;
    g_LSB = opts.g_LSB;
    lsb_V = opts.dac_range_V / 2^opts.dac_bits;     % 1 LSB [V] ≈ 305 µV

    % 制御則に渡す共通パラメータ束（実コードと同名）
    P = struct('g_LSB',g_LSB, 'lsb_V',lsb_V, 'df_max',opts.df_max, ...
               'dN_max',opts.dN_max, 'ema',opts.df_ema, 'Ts',Ts, ...
               'v_min',0.0, 'v_max',5.0);

    if isempty(opts.save_tag), tag=''; else, tag=['_' opts.save_tag]; end

    %% === 実測CSVの読み込み（無ければデモ）=============================
    have_meas = ~isempty(meas_csv) && isfile(meas_csv);
    if have_meas
        T = readtable(meas_csv);
        % --- 必須列の存在チェック（無ければ分かりやすく停止）---
        need = {'time_s','segment','mode','kpe','frfr_unwrapped_ns','ao0_V', ...
                'freq_err_ns_per_s'};
        miss = need(~ismember(need, T.Properties.VariableNames));
        if ~isempty(miss)
            error('CSV に必要な列がありません: %s', strjoin(miss, ', '));
        end
        fprintf('=== 実測CSV読込: %s （%d 行）===\n', meas_csv, height(T));
        t_meas   = T.time_s(:);
        seg_meas = string(T.segment);
        mode_meas= string(T.mode);
        kpe_meas = T.kpe(:);
        frfr_meas= T.frfr_unwrapped_ns(:);
        ao0_meas = T.ao0_V(:);
        df_meas  = T.freq_err_ns_per_s(:);
    else
        if isempty(meas_csv)
            fprintf('=== 【注意】実測CSVが指定されていません → 自己完結デモを実行 ===\n');
        else
            fprintf('=== 【注意】CSVが見つかりません(%s) → 自己完結デモを実行 ===\n', meas_csv);
        end
        [t_meas, seg_meas, mode_meas, kpe_meas, frfr_meas, ao0_meas, df_meas] = ...
            make_demo(opts, P);
        meas_csv = '(demo)';
    end
    N = numel(t_meas);

    %% === プラント同定: df ≈ K·(u − u0) の線形回帰 ======================
    %  実測の周波数差 df を制御電圧 ao0 に回帰し、傾き K と切片から u0 を得る。
    %  df = a·u + b  →  K_hat = a,  u0_hat = -b/a
    %  （定常区間に限らず全区間を使用。HOLD区間は du=0 だが情報として残す）
    good = isfinite(df_meas) & isfinite(ao0_meas);
    if nnz(good) >= 3 && (max(ao0_meas(good)) - min(ao0_meas(good))) > 1e-4
        pp = polyfit(ao0_meas(good), df_meas(good), 1);   % [a b]
        K_hat  = pp(1);
        u0_hat = -pp(2) / pp(1);
        % 決定係数 R^2
        df_fit = polyval(pp, ao0_meas(good));
        ss_res = sum((df_meas(good) - df_fit).^2);
        ss_tot = sum((df_meas(good) - mean(df_meas(good))).^2);
        R2 = 1 - ss_res / max(ss_tot, eps);
        ident_ok = true;
    else
        % 電圧がほぼ動いていない等で回帰不能 → 公称値にフォールバック
        K_hat  = opts.K_nominal;
        u0_hat = opts.u0_nominal;
        R2 = NaN;
        ident_ok = false;
        warning('回帰に十分な電圧変化がありません → 公称 K=%.0f, u0=%.3f を使用', K_hat, u0_hat);
    end

    % シムで使うプラント定数（opts.use_nominal_K で公称固定に切替）
    if opts.use_nominal_K
        K_sim  = opts.K_nominal;
        u0_sim = opts.u0_nominal;
        Klabel = sprintf('公称 K=%.0f', K_sim);
    else
        K_sim  = K_hat;
        u0_sim = u0_hat;
        Klabel = sprintf('同定 K=%.1f', K_sim);
    end

    %% === 区間スケジュールの抽出 ========================================
    %  実測の (segment, mode, kpe) が変化した点を区間境界とする。
    seg_idx = segment_boundaries(seg_meas, mode_meas, kpe_meas);  % 各サンプルの区間番号
    nseg = max(seg_idx);
    segmap = struct('name',{}, 'mode',{}, 'kpe',{}, 'i0',{}, 'i1',{}, 't0',{}, 't1',{});
    for g = 1:nseg
        ii = find(seg_idx == g);
        segmap(g) = struct('name', char(seg_meas(ii(1))), 'mode', char(mode_meas(ii(1))), ...
                           'kpe', kpe_meas(ii(1)), 'i0', ii(1), 'i1', ii(end), ...
                           't0', t_meas(ii(1)), 't1', t_meas(ii(end))); %#ok<AGROW>
    end

    %% === クローズドループ・シミュレーション ============================
    %  実コードと同じ手順を踏むが、アンラップ済み空間で直接シムする
    %  （ラップ→アンラップの折返しは決定論シムでは省略しても等価。後述）。
    phi_sim = nan(N,1);     % シム位相差 FRFR [ns]
    u_sim   = nan(N,1);     % シム制御電圧 [V]
    dN_sim  = nan(N,1);     % シム LSB 段数
    e_sim   = nan(N,1);     % シム位相誤差 [ns]

    % 制御則の内部状態（実コードと同じ）
    df_s = 0;               % EMA 平滑 df
    prev_phi = NaN;         % 前ステップのアンラップ位相
    u_applied = clamp(opts.u_init, P.v_min, P.v_max);

    % 目標 target_adjusted は実コードと同じ mod(.,100) ロジックで初回確定
    T_period = 100;
    phi0 = frfr_meas(1);    % 実測初期 FRFR から開始
    rem0 = mod(phi0 - opts.FRFR_ref, T_period);
    if rem0 > T_period/2, rem0 = rem0 - T_period; end
    target_adjusted = phi0 - rem0;

    phi = phi0;             % 現在のシム位相
    for k = 1:N
        Kp_e = kpe_meas(k);
        mode = mode_meas(k);

        % --- このステップの「観測」= シム位相 ---
        phi_sim(k) = phi;
        e = target_adjusted - phi;
        e_sim(k) = e;

        % --- 周波数誤差 df（数値微分）＋ EMA 平滑（実コードと同一）---
        if isnan(prev_phi)
            df = 0; df_s = 0;
        else
            df = (phi - prev_phi) / Ts;
            df_s = P.ema*df_s + (1-P.ema)*df;
        end
        prev_phi = phi;

        % --- 制御則（逆モデル）: 実コード localcontrol() ---
        [u_next, dN] = localcontrol(mode, Kp_e, e, df_s, u_applied, P);
        u_sim(k)  = u_next;
        dN_sim(k) = dN;
        u_applied = u_next;

        % --- プラント1歩前進: φ[k+1] = φ[k] + Ts·K·(u_next − u0) ---
        %  実機は u を「出した後」次サイクルで効果が出るので、適用後の u_next で進める
        phi = phi + Ts * K_sim * (u_next - u0_sim);
    end

    %% === 区間別 RMS 差（シム vs 実測 FRFR）=============================
    seg_rms = nan(nseg,1);
    for g = 1:nseg
        ii = segmap(g).i0:segmap(g).i1;
        d  = phi_sim(ii) - frfr_meas(ii);
        seg_rms(g) = sqrt(mean(d.^2, 'omitnan'));
    end
    rms_all = sqrt(mean((phi_sim - frfr_meas).^2, 'omitnan'));

    %% === 図(i): FRFR vs time（実測 vs シム）============================
    fig1 = figure('Name','sim vs meas FRFR','NumberTitle','off','Position',[80 80 980 520]);
    plot(t_meas, frfr_meas, 'b-',  'LineWidth',1.3); hold on; grid on;
    plot(t_meas, phi_sim,  'r--', 'LineWidth',1.3);
    yline(target_adjusted, 'k-.', sprintf('目標 %.1f ns', target_adjusted), ...
          'LabelHorizontalAlignment','left', 'HandleVisibility','off');
    ymax = max([frfr_meas; phi_sim], [], 'omitnan');
    for g = 1:nseg
        xline(segmap(g).t0, 'k:', 'HandleVisibility','off');
        text(segmap(g).t0, ymax, sprintf(' %s', segmap(g).name), 'Rotation',90, ...
             'VerticalAlignment','top', 'FontSize',8, 'Interpreter','none');
    end
    xlabel('時間 [s]'); ylabel('FRFR（アンラップ）[ns]');
    legend({'実測 FRFR', sprintf('シム φ（%s, u0=%.3f）', Klabel, u0_sim)}, ...
           'Location','best', 'Interpreter','none');
    title(sprintf('決定論クローズドループ・シム vs 実測 FRFR（全体RMS差=%.2f ns）', rms_all), ...
          'Interpreter','none');
    f1_png = sprintf('sim_frfr_overlay_260610%s.png', tag);
    f1_pdf = sprintf('sim_frfr_overlay_260610%s.pdf', tag);
    exportgraphics(fig1, f1_png, 'Resolution', 300);
    exportgraphics(fig1, f1_pdf, 'ContentType', 'vector');

    %% === 図(ii): 電圧 vs time（実測 vs シム）===========================
    fig2 = figure('Name','sim vs meas Voltage','NumberTitle','off','Position',[80 80 980 520]);
    stairs(t_meas, ao0_meas*1e3, 'b-',  'LineWidth',1.3); hold on; grid on;
    stairs(t_meas, u_sim*1e3,   'r--', 'LineWidth',1.3);
    for g = 1:nseg
        xline(segmap(g).t0, 'k:', 'HandleVisibility','off');
    end
    xlabel('時間 [s]'); ylabel('制御電圧 ao0 [mV]');
    legend({'実測 ao0', 'シム u（デッドバンド階段: 平坦=dN=0）'}, ...
           'Location','best', 'Interpreter','none');
    title('制御電圧の比較（量子化デッドバンドによる階段状変化）', 'Interpreter','none');
    f2_png = sprintf('sim_volt_overlay_260610%s.png', tag);
    f2_pdf = sprintf('sim_volt_overlay_260610%s.pdf', tag);
    exportgraphics(fig2, f2_png, 'Resolution', 300);
    exportgraphics(fig2, f2_pdf, 'ContentType', 'vector');

    %% === 図(iii): K 回帰（df vs u）=====================================
    fig3 = figure('Name','K regression','NumberTitle','off','Position',[80 80 720 520]);
    scatter(ao0_meas(good), df_meas(good), 18, 'b', 'filled', ...
            'MarkerFaceAlpha',0.4); hold on; grid on;
    if ident_ok
        uu = linspace(min(ao0_meas(good)), max(ao0_meas(good)), 50);
        plot(uu, polyval(pp, uu), 'r-', 'LineWidth',1.6);
        yline(0, 'k:', 'HandleVisibility','off');
        legend({'実測 (u, df)', sprintf('回帰: K_{hat}=%.1f, u0=%.3f, R^2=%.2f', ...
                K_hat, u0_hat, R2)}, 'Location','best');
    else
        legend({'実測 (u, df)（回帰不能）'}, 'Location','best');
    end
    xlabel('制御電圧 ao0 [V]'); ylabel('周波数差 df [ns/s]');
    title(sprintf('プラント同定 df≈K·(u−u0)（公称 K=%.0f との比較）', opts.K_nominal));
    f3_png = sprintf('sim_K_regression_260610%s.png', tag);
    f3_pdf = sprintf('sim_K_regression_260610%s.pdf', tag);
    exportgraphics(fig3, f3_png, 'Resolution', 300);
    exportgraphics(fig3, f3_pdf, 'ContentType', 'vector');

    %% === コンソール要約 ================================================
    fprintf('\n========== シミュレーション要約 ==========\n');
    fprintf('入力データ      : %s（%d サンプル, %d 区間）\n', meas_csv, N, nseg);
    if ident_ok
        fprintf('プラント同定    : K_hat=%.1f ns/(V·s)  (公称 860 比 %.2f倍, R^2=%.3f)\n', ...
                K_hat, K_hat/860, R2);
        fprintf('                  u0_hat=%.4f V\n', u0_hat);
        fprintf('                  → K≈860 検証: 同定値は公称の %.0f%% \n', 100*K_hat/860);
    else
        fprintf('プラント同定    : 不能（電圧変化不足）→ 公称 K=%.0f, u0=%.3f を使用\n', K_hat, u0_hat);
    end
    fprintf('シム使用プラント: %s, u0=%.4f V%s\n', Klabel, u0_sim, ...
            ternary(opts.use_nominal_K, '（公称固定）', '（同定値）'));
    fprintf('目標 FRFR       : target_adjusted=%.2f ns（初期 %.2f ns から確定）\n', ...
            target_adjusted, phi0);
    fprintf('全体 RMS 差     : %.3f ns（シム φ vs 実測 FRFR）\n', rms_all);
    fprintf('--- 区間別 RMS 差（シム vs 実測 FRFR）---\n');
    for g = 1:nseg
        fprintf('  %-10s [%-5s k=%.3f] (%4.0f–%4.0f s, %3d点)  RMS=%.3f ns\n', ...
                segmap(g).name, segmap(g).mode, segmap(g).kpe, ...
                segmap(g).t0, segmap(g).t1, segmap(g).i1-segmap(g).i0+1, seg_rms(g));
    end
    fprintf('--- 乖離の解釈 ---\n');
    fprintf('  決定論シムは Δf=K·(u−u0) の理想プラントのみを表現。実測との差は\n');
    fprintf('  以下の決定論モデルが省く要因に由来する:\n');
    fprintf('   ・OCXO の温度ドリフト/経時ドリフト（u0 の緩やかな時変）\n');
    fprintf('   ・FRFR 計測ノイズ（オシロ分解能・短期ジッタ, 260604で定量化済み）\n');
    fprintf('   ・K の動作点依存・非線形性（単一直線回帰では捉えきれない）\n');
    fprintf('   ・アンラップの取りこぼし等の離散事象\n');
    fprintf('  → 区間 RMS が大きい区間ほど上記の実世界要因の寄与が大きい。\n');
    fprintf('保存図          : %s / %s / %s（各 .pdf も）\n', f1_png, f2_png, f3_png);
    fprintf('==========================================\n');

    %% === 返り値 ========================================================
    result = struct( ...
        'meas_csv',     meas_csv, ...
        'K_hat',        K_hat, ...
        'u0_hat',       u0_hat, ...
        'R2',           R2, ...
        'ident_ok',     ident_ok, ...
        'K_sim',        K_sim, ...
        'u0_sim',       u0_sim, ...
        'use_nominal_K',opts.use_nominal_K, ...
        'target_adjusted', target_adjusted, ...
        'rms_all',      rms_all, ...
        'seg_rms',      seg_rms, ...
        'segmap',       segmap, ...
        't',            t_meas, ...
        'frfr_meas',    frfr_meas, ...
        'phi_sim',      phi_sim, ...
        'ao0_meas',     ao0_meas, ...
        'u_sim',        u_sim, ...
        'dN_sim',       dN_sim, ...
        'lsb_V',        lsb_V, ...
        'figs',         {{f1_png, f2_png, f3_png}}, ...
        'figs_pdf',     {{f1_pdf, f2_pdf, f3_pdf}}, ...
        'opts',         opts);
end

%% ====================================================================
%  ローカル関数
%% ====================================================================

function [u_next, dN] = localcontrol(mode, Kp_e, e, df_s, u_applied, P)
% 制御則（frfr_model_260610_v1.m の実コードをそのまま移植）
%   df_des = clamp(Kp_e*e, ±df_max)
%   dN     = round(clamp((df_des - df_s)/g_LSB, ±dN_max))  ← round=量子化デッドバンド
%   du     = dN*lsb_V
%   u_next = clamp(u_applied + du, v_min, v_max)
    if strcmp(mode, 'MODEL')
        df_des = clamp(Kp_e * e, -P.df_max, P.df_max);
        dN_f   = (df_des - df_s) / P.g_LSB;
        dN     = round(clamp(dN_f, -P.dN_max, P.dN_max));
        du     = dN * P.lsb_V;
        u_next = clamp(u_applied + du, P.v_min, P.v_max);
    else    % HOLD（電圧据え置き）
        dN     = 0;
        u_next = u_applied;
    end
end

function seg_idx = segment_boundaries(seg, mode, kpe)
% (segment, mode, kpe) のいずれかが変化した点を新区間境界とし、
% 各サンプルへ 1..nseg の区間番号を割り当てる。
    N = numel(seg);
    seg_idx = ones(N,1);
    g = 1;
    for k = 2:N
        changed = (seg(k) ~= seg(k-1)) || (mode(k) ~= mode(k-1)) ...
                  || ~isequaln(kpe(k), kpe(k-1));
        if changed, g = g + 1; end
        seg_idx(k) = g;
    end
end

function [t, seg, mode, kpe, frfr, ao0, df] = make_demo(opts, P)
% 自己完結デモ: 実測CSVが無い場合に「もっともらしい」ランを合成する。
%   スケジュール: acq(MODEL,0.06) → kpe0.02 → kpe0.04 → kpe0.08 → HOLD
%   プラント: 公称 K=860, u0≈1.54, 初期 FRFR に offset。
%   ここでは制御則＋理想プラントを回して frfr/ao0/df を生成し、
%   さらに実世界らしさのため微小ノイズ＋緩やかドリフトを重畳する。
    Ts    = opts.Ts;
    K     = opts.K_nominal;          % 公称 K
    u0    = opts.u0_nominal;         % 動作点
    Lseg  = max(opts.demo_seg_len, 20);

    sched = { 'acq','MODEL',0.06; ...
              'kpe0.02','MODEL',0.02; ...
              'kpe0.04','MODEL',0.04; ...
              'kpe0.08','MODEL',0.08; ...
              'HOLD','HOLD',0 };
    nS = size(sched,1);
    N  = nS * Lseg;

    t   = (0:N-1)' * Ts;
    seg = strings(N,1); mode = strings(N,1); kpe = zeros(N,1);
    frfr= zeros(N,1);   ao0  = zeros(N,1);   df  = zeros(N,1);

    rng(20260610);                    % 再現性のため固定シード
    drift_rate = 0.03;                % 緩やかな u0 ドリフト [V 相当を ns/s に] ※微小

    % 制御則を回すための状態
    df_s = 0; prev_phi = NaN;
    u_applied = clamp(opts.u_init, P.v_min, P.v_max);
    T_period = 100;

    % 初期 FRFR（目標から少しずらして同期過程を見せる）
    phi = opts.FRFR_ref + 8.0;
    rem0 = mod(phi - opts.FRFR_ref, T_period);
    if rem0 > T_period/2, rem0 = rem0 - T_period; end
    target_adjusted = phi - rem0;

    k = 0;
    for is = 1:nS
        nm = sched{is,1}; md = sched{is,2}; kp = sched{is,3};
        for j = 1:Lseg
            k = k + 1;
            seg(k) = nm; mode(k) = md; kpe(k) = kp;

            e = target_adjusted - phi;
            if isnan(prev_phi), dphi = 0; df_s = 0;
            else, dphi = (phi - prev_phi)/Ts; df_s = P.ema*df_s + (1-P.ema)*dphi; end
            prev_phi = phi;

            [u_next, ~] = localcontrol(md, kp, e, df_s, u_applied, P);
            u_applied = u_next;

            % 観測ノイズ＋緩やかドリフト（実世界らしさ）
            meas_noise = 0.15 * randn;                 % FRFR 計測ノイズ [ns]
            u0_t = u0 + drift_rate*1e-3 * (t(k));      % u0 緩やかドリフト [V]

            frfr(k) = phi + meas_noise;
            ao0(k)  = u_next;
            df(k)   = K * (u_next - u0_t) + 0.05*randn; % 周波数差（ノイズ込み）

            % プラント前進（真値 phi はノイズ無し、ドリフト込み u0_t）
            phi = phi + Ts * K * (u_next - u0_t);
        end
    end
end

function y = clamp(x, lo, hi)
% 値を [lo, hi] に制限
    y = min(max(x, lo), hi);
end

function out = ternary(cond, a, b)
% 簡易三項: cond なら a, でなければ b
    if cond, out = a; else, out = b; end
end
