function result = frfr_model_260610_v1(opts)
%====================================================================
% Phase 2 N/400モデルFB（260610 v1）── 制御方式②／録音1本用
%
%  ★ 録音は制御方式ごとに1本ずつ切るため、このスクリプトは「N/400モデル」
%    専用（別録音）。低ゲインPIDは frfr_pid_lowgain_260610_v1.m。
%
%  狙い: 260608 では Kp_e=0.02 の1点しか試せず、モデルFBは本気の強さで
%        未評価だった。本スクリプトは **Kp_e を区間で掃引**（1録音内で複数強さ）
%        し、録音付きで各 Kp_e の ps級ヒルベルト低周波スペクトルを比較する。
%
%  モデル（260608と同一）: df = g_LSB * N （N=動作点からの整数LSB段数）
%        df_des = clamp(Kp_e*e, ±df_max)
%        dN     = round(clamp((df_des - df_smooth)/g_LSB, ±dN_max))
%        u     += dN*lsb_V
%        ※ round() が量子化デッドバンド → 小補正では電圧据え置き＝静音。
%
%  区間（状態は連続, 各 slot_s 秒）:
%        1. acq         MODEL : 強め Kp_e_acq で素早く同期（解析対象外）
%        2..  kpe<val>  MODEL : Kp_e_list の各値で評価本番（中央10sを解析）
%        last HOLD      HOLD  : 電圧固定の基準（同一録音内の比較対象）
%
%  ▼▼ 実行手順（録音対応・厳守）▼▼
%   1) TASCAM 録音を開始
%   2) 実行 →「t=0 絶対時刻」をメモ
%   3) 終了表示で録音停止
%   4) offset_s =（録音開始 → スクリプトt=0 までの秒数）を控える
%
%  使い方（Current Folder を 260610 に）:
%    R = frfr_model_260610_v1();                         % 既定 Kp_e=[0.02 0.04 0.08]
%    o.Kp_e_list=[0.03 0.06]; R = frfr_model_260610_v1(o);
%    o.slot_s=60; R = frfr_model_260610_v1(o);           % 動作確認
%
%  opts（既定）: slot_s(300=5分) FRFR_ref(25) u_init(1.54)
%               g_LSB(0.26) Kp_e_list([0.02 0.04 0.08]) Kp_e_acq(0.06)
%               df_max(1.5) dN_max(4) df_ema(0.5) Ts(1.0) nOS(3)
%               dac_range_V(20) dac_bits(16) run_tag('')
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('slot_s',300, 'FRFR_ref',25, 'u_init',1.54, ...
                 'g_LSB',0.26, 'Kp_e_list',[0.02 0.04 0.08], 'Kp_e_acq',0.06, ...
                 'df_max',1.5, 'dN_max',4, 'df_ema',0.5, 'Ts',1.0, 'nOS',3, ...
                 'dac_range_V',20, 'dac_bits',16, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    slot = opts.slot_s;  Ts = opts.Ts;  nOS = opts.nOS;
    g_LSB = opts.g_LSB;  df_max = opts.df_max;  dN_max = opts.dN_max;  ema = opts.df_ema;
    lsb_V = opts.dac_range_V / 2^opts.dac_bits;     % 1 LSB [V]

    %% === 区間定義（Kp_e 掃引）=========================================
    SEG = mkseg('acq','MODEL', opts.Kp_e_acq);
    for v = opts.Kp_e_list(:)'
        SEG(end+1) = mkseg(sprintf('kpe%g',v), 'MODEL', v); %#ok<AGROW>
    end
    SEG(end+1) = mkseg('HOLD','HOLD', 0);

    %% === 共通定数 ======================================================
    v_min = 0.0;  v_max = 5.0;
    T_period = 100; JUMP_DETECT = 50; OFFSET_STEP = 100;

    %% === DAQ / Scope ===================================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;
    SAFE_AO0 = 0.0;
    c = onCleanup(@() cleanupDAQ(s, dev, SAFE_AO0)); %#ok<NASGU>

    %% === 状態 ==========================================================
    prev_raw_frfr = NaN;  frfr_offset = 0;  prev_frfr_unwrapped = NaN;
    target_adjusted = NaN;  t_prev = NaN;  df_s = 0;
    u_applied = clamp(opts.u_init, v_min, v_max);

    %% === ログ ==========================================================
    L = struct('t',[], 'seg',strings(0,1), 'mode',strings(0,1), 'kpe',[], 'dt',[], ...
               'raw',[], 'unw',[], 'e',[], 'df',[], 'df_s',[], 'df_des',[], 'dN',[], 'du',[], 'ao0',[]);
    segmap = struct('name',{}, 'mode',{}, 'kpe',{}, 't_start',{}, 't_end',{});

    %% === 開始 ==========================================================
    t_run_start = datetime('now');
    outputSingleScan(s, u_applied);
    fprintf("=== N/400モデルFB v1（制御方式②）開始 ===\n");
    fprintf("★ 録音を先に開始しているか確認！\n");
    fprintf("スクリプト t=0 (絶対時刻): %s  ← 録音対応にメモ\n", datestr(t_run_start, 'yyyy-mm-dd HH:MM:SS'));
    fprintf("各区間 %.0f s | 目標 FRFR=%.1f ns | u_init=%.3f V\n", slot, opts.FRFR_ref, u_applied);
    fprintf("モデル: df=g_LSB*N, g_LSB=%.3f ns/s/LSB (1LSB=%.1f µV) | df_max=%.2f dN_max=%d ema=%.2f Ts=%.2f nOS=%d\n", ...
        g_LSB, lsb_V*1e6, df_max, dN_max, ema, Ts, nOS);
    fprintf("Kp_e 掃引: acq=%.3f, 本番=[%s]\n", opts.Kp_e_acq, num2str(opts.Kp_e_list));

    %% === 区間ループ ====================================================
    for iseg = 1:numel(SEG)
        seg = SEG(iseg);  Kp_e = seg.kpe;
        seg_t0 = seconds(datetime('now') - t_run_start);
        fprintf("\n===== 区間 %d/%d: %-8s [%s] Kp_e=%.3f =====\n", iseg, numel(SEG), seg.name, seg.mode, Kp_e);

        seg_started = false;
        while true
            t = seconds(datetime('now') - t_run_start);
            if seg_started && (t - seg_t0 > slot), break; end
            seg_started = true;

            % ---- FRFR 読み取り（nOS 回中央値）----
            raw_vals = nan(1, nOS);  read_ok = true;
            for k = 1:nOS
                try
                    writeline(dev, "MEAS:ADV:P3:VAL?");
                    raw_vals(k) = str2double(readline(dev)) * 1e9;
                catch ME
                    warning("FRFR read error: %s", ME.message); read_ok = false; break;
                end
            end
            if ~read_ok, break; end
            raw_frfr = median(raw_vals, 'omitnan');

            % ---- アンラップ ----
            if ~isnan(prev_raw_frfr)
                d = raw_frfr - prev_raw_frfr;
                if     d <= -JUMP_DETECT, frfr_offset = frfr_offset + OFFSET_STEP;
                elseif d >= +JUMP_DETECT, frfr_offset = frfr_offset - OFFSET_STEP; end
            end
            frfr_unw = raw_frfr + frfr_offset;
            prev_raw_frfr = raw_frfr;

            % ---- 周波数誤差 df ＋ EMA平滑 ----
            dt = t - t_prev;
            if isnan(prev_frfr_unwrapped), df = 0; df_s = 0;
            else, df = (frfr_unw - prev_frfr_unwrapped)/Ts; df_s = ema*df_s + (1-ema)*df; end
            prev_frfr_unwrapped = frfr_unw;  t_prev = t;

            % ---- 目標（初回で確定）----
            if isnan(target_adjusted)
                rem = mod(frfr_unw - opts.FRFR_ref, T_period);
                if rem > T_period/2, rem = rem - T_period; end
                target_adjusted = frfr_unw - rem;
                fprintf("初期 FRFR=%.2f → 調整後目標=%.2f ns\n", frfr_unw, target_adjusted);
            end
            e = target_adjusted - frfr_unw;

            % ---- 制御則（逆モデル）----
            if strcmp(seg.mode, 'MODEL')
                df_des = clamp(Kp_e * e, -df_max, df_max);
                dN_f   = (df_des - df_s) / g_LSB;
                dN     = round(clamp(dN_f, -dN_max, dN_max));
                du     = dN * lsb_V;
                u_next = clamp(u_applied + du, v_min, v_max);
            else  % HOLD
                df_des = NaN;  dN = 0;  du = 0;  u_next = u_applied;
            end

            % ---- 出力 ----
            try, outputSingleScan(s, u_next);
            catch ME, warning("DAQ output error: %s", ME.message); break; end
            u_applied = u_next;

            % ---- ログ ----
            L.t(end+1)=t; L.seg(end+1,1)=seg.name; L.mode(end+1,1)=seg.mode; L.kpe(end+1)=Kp_e; %#ok<AGROW>
            L.dt(end+1)=dt; L.raw(end+1)=raw_frfr; L.unw(end+1)=frfr_unw; %#ok<AGROW>
            L.e(end+1)=e; L.df(end+1)=df; L.df_s(end+1)=df_s; %#ok<AGROW>
            L.df_des(end+1)=df_des; L.dN(end+1)=dN; L.du(end+1)=du; L.ao0(end+1)=u_applied; %#ok<AGROW>

            fprintf("t=%6.1f [%-8s %s k=%.3f] FRFR=%.2f e=%.2f df=%.3f(s=%.3f) dN=%+d ao0=%.4f\n", ...
                t, seg.name, seg.mode, Kp_e, frfr_unw, e, df, df_s, dN, u_applied);
            pause(Ts);
        end
        seg_t1 = seconds(datetime('now') - t_run_start);
        segmap(end+1) = struct('name',seg.name,'mode',seg.mode,'kpe',Kp_e,'t_start',seg_t0,'t_end',seg_t1); %#ok<AGROW>
    end
    fprintf("\n=== 終了。録音を停止してよい ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    log_name = sprintf('frfr_model_%s%s.csv', ts, tag);
    seg_name = sprintf('frfr_model_%s%s_segmap.csv', ts, tag);

    writetable(table(L.t(:), L.seg(:), L.mode(:), L.kpe(:), L.dt(:), L.raw(:), L.unw(:), ...
        L.e(:), L.df(:), L.df_s(:), L.df_des(:), L.dN(:), L.du(:), L.ao0(:), 'VariableNames', ...
        {'time_s','segment','mode','kpe','dt_actual_s','frfr_raw_ns','frfr_unwrapped_ns', ...
         'e_phase_ns','freq_err_ns_per_s','freq_err_smooth_ns_per_s','df_des_ns_per_s', ...
         'dN_lsb','delta_u_V','ao0_V'}), log_name);
    fprintf("ログ保存: %s\n", log_name);

    smt = struct2table(segmap);
    smt.abs_start = string(datestr(t_run_start + seconds([segmap.t_start]'), 'HH:MM:SS'));
    writetable(smt, seg_name);
    fprintf("区間時刻表: %s\n", seg_name);

    %% === 区間サマリ ====================================================
    fprintf("\n--- 区間サマリ（終端60s std / 電圧移動量 / LSB操作）---\n");
    for k = 1:numel(segmap)
        sm = segmap(k);
        idx = (L.t > sm.t_end - 60) & (L.t <= sm.t_end);
        if sum(idx) > 5
            s_std = std(L.unw(idx));
            if strcmp(sm.mode,'MODEL')
                ia = (L.t >= sm.t_start) & (L.t <= sm.t_end);
                fprintf("%-8s [MODEL k=%.3f] std=%.3f ns | 移動量=%.4f V | LSB操作=%d/%d\n", ...
                    sm.name, sm.kpe, s_std, sum(abs(L.du(ia))), sum(L.dN(ia)~=0), sum(ia));
            else
                fprintf("%-8s [HOLD]         std=%.3f ns\n", sm.name, s_std);
            end
        end
    end

    %% === クイック図 ====================================================
    fig = figure('Name','model v1','NumberTitle','off','Position',[80 80 950 560]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile; plot(L.t, L.unw, 'b-'); hold on; grid on;
    if ~isnan(target_adjusted), yline(target_adjusted,'r--',sprintf('Target %.1f',target_adjusted)); end
    for k=1:numel(segmap), xline(segmap(k).t_start,'k:'); text(segmap(k).t_start,max(L.unw,[],'omitnan'),sprintf(' %s',segmap(k).name),'Rotation',90,'VerticalAlignment','top','FontSize',8,'Interpreter','none'); end
    ylabel('FRFR unwrapped [ns]'); title('N/400モデルFB v1（Kp_e掃引）: FRFR(上) と 電圧(下)');
    nexttile; plot(L.t, L.ao0*1e3, 'r-'); grid on;
    for k=1:numel(segmap), xline(segmap(k).t_start,'k:'); end
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(fig, sprintf('frfr_model_%s%s.pdf', ts, tag), 'ContentType','vector');

    result = struct('log_csv',log_name, 'segmap_csv',seg_name, ...
        'target_adjusted',target_adjusted, 'segmap',segmap, ...
        'lsb_V',lsb_V, 't_run_start',t_run_start, 'opts',opts);
end

%% === ヘルパー =========================================================
function seg = mkseg(name, mode, kpe), seg = struct('name',name, 'mode',mode, 'kpe',kpe); end
function y = clamp(x, lo, hi), y = min(max(x, lo), hi); end
function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
