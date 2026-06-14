function result = frfr_pid_lowgain_260610_v1(opts)
%====================================================================
% Phase 2 低ゲインPID FB（260610 v1）── 制御方式①／録音1本用
%
%  ★ 録音は制御方式ごとに1本ずつ切るため、このスクリプトは「低ゲインPID」
%    専用。N/400モデルは frfr_model_260610_v1.m（別録音）で取る。
%
%  狙い: 260608 で「FBゲインを下げるとハンチングが消える」とオシロ上で判明。
%        その本命 Ki,Kd ×0.1（g0.10相当）を **録音付き** で回し、
%        ps級ヒルベルト解析で低周波スペクトルが下がるかを確認する。
%
%  制御則（260604/260608 と同一, ゲインだけ gain_scale 倍）:
%        du = clamp(gain_scale*Ki*e - gain_scale*Kd*df, -du_max, du_max)
%
%  区間（各 slot_s 秒, 状態は連続）:
%        1. acq  FB   : 低ゲインで同期確立（解析対象外のウォームアップ）
%        2. main FB   : 評価本番（この中央10sをヒルベルト解析）
%        3. HOLD HOLD : 電圧固定の基準（同一録音内の比較対象）
%
%  ▼▼ 実行手順（録音と対応づけるため厳守）▼▼
%   1) TASCAM 録音を開始（CH1→L, CH2→R, 48k/192k）
%   2) このスクリプトを実行 → 画面に出る「t=0 絶対時刻」を必ずメモ
%   3) 区間ループ終了の表示が出たら録音を停止
%   4) offset_s = (録音開始の絶対時刻 → スクリプトt=0 までの秒数) を控える
%      （録音を先に回した秒数。例: 10秒先に録音開始 → offset_s=+10）
%
%  使い方（Current Folder を 260610 に）:
%    R = frfr_pid_lowgain_260610_v1();                 % 各区間 既定 slot_s
%    o.slot_s=60; R = frfr_pid_lowgain_260610_v1(o);   % 動作確認（各1分）
%
%  opts（既定）: slot_s(300=5分) FRFR_ref(25) u_init(1.54)
%               Ki(0.0003) Kd(0.0018) gain_scale(0.10)
%               Ts(0.5) nOS(1) du_max(0.05) run_tag('')
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('slot_s',300, 'FRFR_ref',25, 'u_init',1.54, ...
                 'Ki',0.0003, 'Kd',0.0018, 'gain_scale',0.10, ...
                 'Ts',0.5, 'nOS',1, 'du_max',0.05, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    slot = opts.slot_s;  Ts = opts.Ts;  nOS = opts.nOS;
    Ki = opts.Ki * opts.gain_scale;     % 実効ゲイン（×0.1）
    Kd = opts.Kd * opts.gain_scale;

    %% === 区間定義 ======================================================
    SEG = [ mkseg('acq','FB'); mkseg('main','FB'); mkseg('HOLD','HOLD') ];

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
    target_adjusted = NaN;  t_prev = NaN;
    u_applied = clamp(opts.u_init, v_min, v_max);

    %% === ログ ==========================================================
    L = struct('t',[], 'seg',strings(0,1), 'mode',strings(0,1), 'dt',[], ...
               'raw',[], 'unw',[], 'e',[], 'df',[], 'du',[], 'ao0',[]);
    segmap = struct('name',{}, 'mode',{}, 't_start',{}, 't_end',{});

    %% === 開始 ==========================================================
    t_run_start = datetime('now');
    outputSingleScan(s, u_applied);
    fprintf("=== 低ゲインPID FB v1（制御方式①）開始 ===\n");
    fprintf("★ 録音を先に開始しているか確認！\n");
    fprintf("スクリプト t=0 (絶対時刻): %s  ← 録音対応にメモ\n", datestr(t_run_start, 'yyyy-mm-dd HH:MM:SS'));
    fprintf("各区間 %.0f s | 目標 FRFR=%.1f ns | u_init=%.3f V | 実効 Ki=%.5f Kd=%.5f (×%.2f) | Ts=%.2f nOS=%d\n", ...
        slot, opts.FRFR_ref, u_applied, Ki, Kd, opts.gain_scale, Ts, nOS);

    %% === 区間ループ ====================================================
    for iseg = 1:numel(SEG)
        seg = SEG(iseg);
        seg_t0 = seconds(datetime('now') - t_run_start);
        fprintf("\n===== 区間 %d/%d: %-5s [%s] =====\n", iseg, numel(SEG), seg.name, seg.mode);

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

            % ---- 周波数誤差（公称 Ts で割る）----
            dt = t - t_prev;
            if isnan(prev_frfr_unwrapped), df = 0;
            else, df = (frfr_unw - prev_frfr_unwrapped) / Ts; end
            prev_frfr_unwrapped = frfr_unw;  t_prev = t;

            % ---- 目標（初回FBで確定）----
            if isnan(target_adjusted)
                rem = mod(frfr_unw - opts.FRFR_ref, T_period);
                if rem > T_period/2, rem = rem - T_period; end
                target_adjusted = frfr_unw - rem;
                fprintf("初期 FRFR=%.2f → 調整後目標=%.2f ns\n", frfr_unw, target_adjusted);
            end
            e = target_adjusted - frfr_unw;

            % ---- 制御則 ----
            if strcmp(seg.mode, 'FB')
                du = clamp(Ki*e - Kd*df, -opts.du_max, opts.du_max);
                u_next = clamp(u_applied + du, v_min, v_max);
            else  % HOLD
                du = 0;  u_next = u_applied;
            end

            % ---- 出力 ----
            try, outputSingleScan(s, u_next);
            catch ME, warning("DAQ output error: %s", ME.message); break; end
            u_applied = u_next;

            % ---- ログ ----
            L.t(end+1)=t; L.seg(end+1,1)=seg.name; L.mode(end+1,1)=seg.mode; %#ok<AGROW>
            L.dt(end+1)=dt; L.raw(end+1)=raw_frfr; L.unw(end+1)=frfr_unw; %#ok<AGROW>
            L.e(end+1)=e; L.df(end+1)=df; L.du(end+1)=du; L.ao0(end+1)=u_applied; %#ok<AGROW>

            fprintf("t=%6.1f [%-4s %s] FRFR=%.2f e=%.2f df=%.3f du=%+.5f ao0=%.4f\n", ...
                t, seg.name, seg.mode, frfr_unw, e, df, du, u_applied);
            pause(Ts);
        end
        seg_t1 = seconds(datetime('now') - t_run_start);
        segmap(end+1) = struct('name',seg.name,'mode',seg.mode,'t_start',seg_t0,'t_end',seg_t1); %#ok<AGROW>
    end
    fprintf("\n=== 終了。録音を停止してよい ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    log_name = sprintf('frfr_pid_lowgain_%s%s.csv', ts, tag);
    seg_name = sprintf('frfr_pid_lowgain_%s%s_segmap.csv', ts, tag);

    writetable(table(L.t(:), L.seg(:), L.mode(:), L.dt(:), L.raw(:), L.unw(:), ...
        L.e(:), L.df(:), L.du(:), L.ao0(:), 'VariableNames', ...
        {'time_s','segment','mode','dt_actual_s','frfr_raw_ns','frfr_unwrapped_ns', ...
         'e_phase_ns','freq_err_ns_per_s','delta_u_V','ao0_V'}), log_name);
    fprintf("ログ保存: %s\n", log_name);

    smt = struct2table(segmap);
    smt.abs_start = string(datestr(t_run_start + seconds([segmap.t_start]'), 'HH:MM:SS'));
    writetable(smt, seg_name);
    fprintf("区間時刻表: %s\n", seg_name);

    %% === 区間サマリ ====================================================
    fprintf("\n--- 区間サマリ（終端60s std）---\n");
    for k = 1:numel(segmap)
        sm = segmap(k);
        idx = (L.t > sm.t_end - 60) & (L.t <= sm.t_end);
        if sum(idx) > 5
            s_std = std(L.unw(idx));
            if strcmp(sm.mode,'FB')
                ia = (L.t >= sm.t_start) & (L.t <= sm.t_end);
                fprintf("%-5s [FB]   std=%.3f ns | 電圧移動量=%.4f V\n", sm.name, s_std, sum(abs(L.du(ia))));
            else
                fprintf("%-5s [HOLD] std=%.3f ns\n", sm.name, s_std);
            end
        end
    end

    %% === クイック図 ====================================================
    fig = figure('Name','pid_lowgain v1','NumberTitle','off','Position',[80 80 950 560]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile; plot(L.t, L.unw, 'b-'); hold on; grid on;
    if ~isnan(target_adjusted), yline(target_adjusted,'r--',sprintf('Target %.1f',target_adjusted)); end
    for k=1:numel(segmap), xline(segmap(k).t_start,'k:'); text(segmap(k).t_start,max(L.unw,[],'omitnan'),sprintf(' %s',segmap(k).name),'Rotation',90,'VerticalAlignment','top','FontSize',8); end
    ylabel('FRFR unwrapped [ns]'); title('低ゲインPID FB v1: FRFR(上) と 電圧(下)');
    nexttile; plot(L.t, L.ao0*1e3, 'r-'); grid on;
    for k=1:numel(segmap), xline(segmap(k).t_start,'k:'); end
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(fig, sprintf('frfr_pid_lowgain_%s%s.pdf', ts, tag), 'ContentType','vector');

    result = struct('log_csv',log_name, 'segmap_csv',seg_name, ...
        'target_adjusted',target_adjusted, 'segmap',segmap, ...
        't_run_start',t_run_start, 'opts',opts);
end

%% === ヘルパー =========================================================
function seg = mkseg(name, mode), seg = struct('name',name, 'mode',mode); end
function y = clamp(x, lo, hi), y = min(max(x, lo), hi); end
function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
