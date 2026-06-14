function result = frfr_phase2_gainsweep_260608_v1(opts)
%====================================================================
% Phase 2 FBゲイン掃引テスト (260608 v1)  ── 方向1：ゲイン調整
%
% 目的:
%   実測 K≈860 ns/(V·s)（260605）は従来想定 K=81 の約10倍。
%   現行FBゲイン(Ki=0.0003,Kd=0.0018)はK=81前提なのでループゲインが
%   約10倍過大 → 260604 の 0.6Hz ハンチングの有力原因。
%   そこで Ki,Kd を共通スケール係数で掃引し、各区間の終端std(ハンチング)
%   と電圧移動量を比較して「ゲインを下げるとハンチングが減るか」を実測する。
%
% 制御則（260604_v1 と同一。ゲインだけ scale 倍）:
%   du = clamp(scale*Ki*e - scale*Kd*df, -du_max, du_max)
%   ※ Ts/nOS は全区間で固定 → 差はゲインのみに帰属させる。
%
% 区間（既定 各 slot_s 秒, 連続して状態を引き継ぐ）:
%   1. acq   FB  scale=0.10 : まず静かに同期させる（ウォームアップ）
%   2. g1.0  FB  scale=1.00 : 現行ゲイン（K=81設計, ハンチング想定）
%   3. g0.30 FB  scale=0.30
%   4. g0.10 FB  scale=0.10 : K≈860 に整合（本命）
%   5. g0.03 FB  scale=0.03
%   6. HOLD  HOLD           : 電圧固定（無制御の基準, 260604で最良34ps）
%
% 評価: 各区間 終端60s の FRFR(unwrapped) std [ns] が小さいほどハンチング小。
%       FB区間は電圧移動量 Σ|du| [V] も併記（動かさないほど静か）。
%
% WAV対応: 録音と併用する場合、表示される「t=0 絶対時刻」をメモし、
%          segmap.csv の t_start/t_end にオフセットを足して各区間窓を切る。
%
% 使い方（Current Folder を 260608 に）:
%   frfr_phase2_gainsweep_260608_v1();                 % 既定（各 slot_s）
%   o.slot_s = 60; frfr_phase2_gainsweep_260608_v1(o); % 動作確認（各1分）
%
% opts（既定）: slot_s(180) FRFR_ref(25) u_init(1.54)
%              Ki(0.0003) Kd(0.0018) Ts(0.5) nOS(1) du_max(0.05) run_tag('')
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('slot_s',180, 'FRFR_ref',25, 'u_init',1.54, ...
                 'Ki',0.0003, 'Kd',0.0018, 'Ts',0.5, 'nOS',1, ...
                 'du_max',0.05, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    slot = opts.slot_s;  Ki = opts.Ki;  Kd = opts.Kd;  Ts = opts.Ts;  nOS = opts.nOS;

    %% === 区間定義（ゲインだけ変える）==================================
    %            name     mode   scale
    SEG = [ ...
        mkseg('acq',   'FB',   0.10); ...
        mkseg('g1.0',  'FB',   1.00); ...
        mkseg('g0.30', 'FB',   0.30); ...
        mkseg('g0.10', 'FB',   0.10); ...
        mkseg('g0.03', 'FB',   0.03); ...
        mkseg('HOLD',  'HOLD', 0.00)];

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

    %% === 状態（区間をまたいで連続）=====================================
    prev_raw_frfr = NaN;  frfr_offset = 0;  prev_frfr_unwrapped = NaN;
    target_adjusted = NaN;  t_prev = NaN;
    u_applied = clamp(opts.u_init, v_min, v_max);

    %% === ログ ==========================================================
    L = struct('t',[], 'seg',strings(0,1), 'mode',strings(0,1), 'scale',[], ...
               'dt',[], 'raw',[], 'unw',[], 'e',[], 'df',[], 'du',[], 'ao0',[]);
    segmap = struct('name',{}, 'mode',{}, 'scale',{}, 't_start',{}, 't_end',{});

    %% === 開始（最初から u_init を出す = 0526/0604 と同じ起動）==========
    t_run_start = datetime('now');
    outputSingleScan(s, u_applied);
    fprintf("=== FBゲイン掃引テスト v1 開始 ===\n");
    fprintf("スクリプト t=0 (絶対時刻): %s\n", datestr(t_run_start, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(">>> 録音併用なら開始時刻をメモ（WAV対応に使う）<<<\n");
    fprintf("各区間 %.0f s | 目標 FRFR=%.1f ns | u_init=%.3f V | base Ki=%.4f Kd=%.4f | Ts=%.2f nOS=%d\n", ...
        slot, opts.FRFR_ref, u_applied, Ki, Kd, Ts, nOS);

    %% === 区間ループ ====================================================
    for iseg = 1:numel(SEG)
        seg = SEG(iseg);
        seg_t0 = seconds(datetime('now') - t_run_start);
        fprintf("\n===== 区間 %d/%d: %-6s [%s] scale=%.2f (Ki=%.5f Kd=%.5f) =====\n", ...
            iseg, numel(SEG), seg.name, seg.mode, seg.scale, seg.scale*Ki, seg.scale*Kd);

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

            % ---- 周波数誤差（公称 Ts で割る; 0526/0604 と同じ）----
            dt = t - t_prev;   % 実周期（ログ用のみ）
            if isnan(prev_frfr_unwrapped)
                df = 0;
            else
                df = (frfr_unw - prev_frfr_unwrapped) / Ts;
            end
            prev_frfr_unwrapped = frfr_unw;  t_prev = t;

            % ---- 目標（初回FBで確定。以降は全区間で共通）----
            if isnan(target_adjusted)
                rem = mod(frfr_unw - opts.FRFR_ref, T_period);
                if rem > T_period/2, rem = rem - T_period; end
                target_adjusted = frfr_unw - rem;
                fprintf("初期 FRFR=%.2f → 調整後目標=%.2f ns\n", frfr_unw, target_adjusted);
            end
            e = target_adjusted - frfr_unw;

            % ---- 制御則（ゲインだけ scale 倍）----
            if strcmp(seg.mode, 'FB')
                du = clamp(seg.scale*Ki*e - seg.scale*Kd*df, -opts.du_max, opts.du_max);
                u_next = clamp(u_applied + du, v_min, v_max);
            else  % HOLD
                du = 0;  u_next = u_applied;   % 直前のロック電圧を保持
            end

            % ---- 出力 ----
            try
                outputSingleScan(s, u_next);
            catch ME
                warning("DAQ output error: %s", ME.message); break;
            end
            u_applied = u_next;

            % ---- ログ ----
            L.t(end+1)=t; L.seg(end+1,1)=seg.name; L.mode(end+1,1)=seg.mode; %#ok<AGROW>
            L.scale(end+1)=seg.scale; L.dt(end+1)=dt; %#ok<AGROW>
            L.raw(end+1)=raw_frfr; L.unw(end+1)=frfr_unw; %#ok<AGROW>
            L.e(end+1)=e; L.df(end+1)=df; L.du(end+1)=du; L.ao0(end+1)=u_applied; %#ok<AGROW>

            fprintf("t=%6.1f [%-5s %s s=%.2f] FRFR=%.2f e=%.2f df=%.3f du=%+.5f ao0=%.4f\n", ...
                t, seg.name, seg.mode, seg.scale, frfr_unw, e, df, du, u_applied);

            pause(Ts);
        end

        seg_t1 = seconds(datetime('now') - t_run_start);
        segmap(end+1) = struct('name',seg.name, 'mode',seg.mode, 'scale',seg.scale, ...
            't_start',seg_t0, 't_end',seg_t1); %#ok<AGROW>
    end
    fprintf("\n=== 掃引テスト v1 終了 ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    log_name = sprintf('frfr_gainsweep_%s%s.csv', ts, tag);
    seg_name = sprintf('frfr_gainsweep_%s%s_segmap.csv', ts, tag);

    writetable(table(L.t(:), L.seg(:), L.mode(:), L.scale(:), L.dt(:), L.raw(:), ...
        L.unw(:), L.e(:), L.df(:), L.du(:), L.ao0(:), 'VariableNames', ...
        {'time_s','segment','mode','gain_scale','dt_actual_s','frfr_raw_ns', ...
         'frfr_unwrapped_ns','e_phase_ns','freq_err_ns_per_s','delta_u_V','ao0_V'}), log_name);
    fprintf("ログ保存: %s\n", log_name);

    smt = struct2table(segmap);
    smt.abs_start = string(datestr(t_run_start + seconds([segmap.t_start]'), 'HH:MM:SS'));
    writetable(smt, seg_name);
    fprintf("区間時刻表: %s\n", seg_name);

    %% === 区間サマリ（終端60s std と 電圧移動量）=======================
    fprintf("\n--- 区間サマリ（終端60sのstd ↓ほどハンチング小）---\n");
    for k = 1:numel(segmap)
        sm = segmap(k);
        idx = (L.t > sm.t_end - 60) & (L.t <= sm.t_end);
        if sum(idx) > 5
            s_std = std(L.unw(idx));
            if strcmp(sm.mode,'FB')
                idx_all = (L.t >= sm.t_start) & (L.t <= sm.t_end);
                travel = sum(abs(L.du(idx_all)));
                fprintf("%-6s [FB s=%.2f] std=%.3f ns | 電圧移動量=%.4f V\n", ...
                    sm.name, sm.scale, s_std, travel);
            else
                fprintf("%-6s [HOLD]      std=%.3f ns\n", sm.name, s_std);
            end
        end
    end

    %% === プロット ======================================================
    fig = figure('Name','gainsweep v1: FRFR & ao0','NumberTitle','off','Position',[80 80 950 560]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile;
    plot(L.t, L.unw, 'b-', 'LineWidth', 1.0); hold on;
    if ~isnan(target_adjusted)
        yline(target_adjusted, 'r--', sprintf('Target %.1f', target_adjusted));
    end
    for k = 1:numel(segmap)
        xline(segmap(k).t_start, 'k:');
        text(segmap(k).t_start, max(L.unw,[],'omitnan'), sprintf(' %s', segmap(k).name), ...
            'Rotation',90, 'VerticalAlignment','top', 'FontSize',8);
    end
    grid on; ylabel('FRFR (unwrapped) [ns]'); title('FBゲイン掃引 v1: FRFR(上) と 制御電圧(下)');
    nexttile;
    plot(L.t, L.ao0*1e3, 'r-'); grid on;
    for k = 1:numel(segmap), xline(segmap(k).t_start, 'k:'); end
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(fig, sprintf('frfr_gainsweep_%s%s.pdf', ts, tag), 'ContentType','vector');

    %% === 結果 ==========================================================
    result = struct('log_csv',log_name, 'segmap_csv',seg_name, ...
        'target_adjusted',target_adjusted, 'segmap',segmap, ...
        't_run_start',t_run_start, 'opts',opts);
end

%% === ヘルパー =========================================================
function seg = mkseg(name, mode, scale)
    seg = struct('name',name, 'mode',mode, 'scale',scale);
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
