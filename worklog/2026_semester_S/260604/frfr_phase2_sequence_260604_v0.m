function result = frfr_phase2_sequence_260604_v0(opts)
%====================================================================
% Phase 2 一気通貫シーケンス (260604)
%   録音(TASCAM)は回しっぱなしにして、本スクリプトを1回実行するだけで
%   6区間を自動で流す。各区間の開始/終了時刻を segmap に保存するので、
%   あとで WAV を区間ごとに切り出して eval_jitter で評価できる。
%
% 区間（既定: 各 5 分 = 300 s, 合計 約25分 + 先頭マーカー）:
%   1. 基準   FB   : Ts=0.3, nOS=1,  deadband=0,   du_max=0.05  （まず同期）
%   2. HOLD1  HOLD : 電圧固定（基準）
%   3. #3slow FB   : Ts=1.0  …更新をゆっくり
%   4. #4avg  FB   : nOS=5   …オシロ5回読み平均
%   5. gentle FB   : Ts=1.0, nOS=5, deadband=0.5, du_max=0.01  （仕上げ）
%
% 状態は区間をまたいで連続:
%   ・アンラップ / target / 電圧 を引き継ぐ（HOLD は直前 FB のロック電圧を保持）
%   ・#3→#4→仕上げ は前区間の終端電圧から継続（再ロックの過渡を入れない）
%
% 先頭マーカー:
%   実験開始前に marker_s 秒だけ 0V を出す。録音には 0V→u_init の段差が
%   現れるので、その位置を WAV 上の「スクリプト t=0」基準に使える。
%
% 使い方:
%   frfr_phase2_sequence_260604_v0();                 % 既定（各5分）
%   o.slot_s = 180; frfr_phase2_sequence_260604_v0(o);% 動作確認用に各3分
%
% opts（既定）: slot_s(300) marker_s(10) FRFR_ref(25) u_init(1.54)
%              Ki(0.0003) Kd(0.0018) run_tag('')
%
% 出力 CSV:
%   frfr_phase2_seq_<ts>.csv        … 全ログ（segment / mode 列つき）
%   frfr_phase2_seq_<ts>_segmap.csv … 区間の時刻表（解析窓の元）
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('slot_s',300, 'marker_s',10, 'FRFR_ref',25, 'u_init',1.54, ...
                 'Ki',0.0003, 'Kd',0.0018, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    slot = opts.slot_s;  Ki = opts.Ki;  Kd = opts.Kd;

    %% === 区間定義（ここを編集すればシーケンスを変えられる）=============
    %            name      mode    dur   Ts  nOS deadband du_max
    SEG = [ ...
        mkseg('kijun',  'FB',   slot, 0.3, 1, 0.0,  0.05); ...
        mkseg('HOLD1',  'HOLD', slot, 0.3, 1, 0.0,  0.05); ...
        mkseg('p3slow', 'FB',   slot, 1.0, 1, 0.0,  0.05); ...
        mkseg('p4avg',  'FB',   slot, 0.3, 5, 0.0,  0.05); ...
        mkseg('gentle', 'FB',   slot, 1.0, 5, 0.5,  0.01)];

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
    L = struct('t',[], 'seg',strings(0,1), 'mode',strings(0,1), 'dt',[], ...
               'raw',[], 'unw',[], 'e',[], 'df',[], 'du',[], 'ao0',[]);
    segmap = struct('name',{}, 'mode',{}, 't_start',{}, 't_end',{}, ...
                    'Ts',{}, 'nOS',{}, 'deadband',{}, 'du_max',{});

    %% === 開始 ==========================================================
    t_run_start = datetime('now');
    fprintf("=== 一気通貫シーケンス 開始 ===\n");
    fprintf("スクリプト t=0 (絶対時刻): %s\n", datestr(t_run_start, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(">>> 録音開始の時刻をメモしておくこと（WAV との対応に使う）<<<\n");
    fprintf("各区間 %.0f s | 目標 FRFR=%.1f ns | Ki=%.4f Kd=%.4f\n", slot, opts.FRFR_ref, Ki, Kd);

    % --- 先頭マーカー（0V を marker_s 秒）---
    if opts.marker_s > 0
        fprintf("--- マーカー: 0V を %.0f s 出力（録音の段差で t=0 を特定）---\n", opts.marker_s);
        outputSingleScan(s, 0);
        mk_start = seconds(datetime('now') - t_run_start);
        while seconds(datetime('now') - t_run_start) - mk_start <= opts.marker_s
            pause(0.3);
        end
    end
    outputSingleScan(s, u_applied);   % 実験開始電圧へ（ここで段差が出る）

    %% === 区間ループ ====================================================
    for iseg = 1:numel(SEG)
        seg = SEG(iseg);
        seg_t0 = seconds(datetime('now') - t_run_start);
        fprintf("\n===== 区間 %d/%d: %s [%s] (Ts=%.2f nOS=%d db=%.2f du=%.3f) =====\n", ...
            iseg, numel(SEG), seg.name, seg.mode, seg.Ts, seg.nOS, seg.deadband, seg.du_max);

        seg_started = false;
        while true
            t_top = datetime('now');
            t = seconds(t_top - t_run_start);
            if seg_started && (t - seg_t0 > seg.dur), break; end
            seg_started = true;

            % ---- FRFR 読み取り（nOS 回中央値）----
            raw_vals = nan(1, seg.nOS);  read_ok = true;
            for k = 1:seg.nOS
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

            % ---- dt / 周波数誤差 ----
            dt = t - t_prev;
            if isnan(dt) || dt <= 0, dt_d = seg.Ts; else, dt_d = dt; end
            if isnan(prev_frfr_unwrapped), df = 0; else, df = (frfr_unw - prev_frfr_unwrapped)/dt_d; end
            prev_frfr_unwrapped = frfr_unw;  t_prev = t;

            % ---- 制御則 ----
            if strcmp(seg.mode, 'FB')
                if isnan(target_adjusted)
                    rem = mod(frfr_unw - opts.FRFR_ref, T_period);
                    if rem > T_period/2, rem = rem - T_period; end
                    target_adjusted = frfr_unw - rem;
                    fprintf("初期 FRFR=%.2f → 調整後目標=%.2f ns\n", frfr_unw, target_adjusted);
                end
                e = target_adjusted - frfr_unw;
                if abs(e) <= seg.deadband
                    du = 0;
                else
                    du = clamp(Ki*e - Kd*df, -seg.du_max, seg.du_max);
                end
                u_next = clamp(u_applied + du, v_min, v_max);
            else  % HOLD
                if isnan(target_adjusted), e = NaN; else, e = target_adjusted - frfr_unw; end
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
            L.dt(end+1)=dt; L.raw(end+1)=raw_frfr; L.unw(end+1)=frfr_unw;     %#ok<AGROW>
            L.e(end+1)=e; L.df(end+1)=df; L.du(end+1)=du; L.ao0(end+1)=u_applied; %#ok<AGROW>

            fprintf("t=%6.1f [%-6s %s] FRFR=%.2f e=%.2f df=%.3f du=%.5f ao0=%.4f\n", ...
                t, seg.name, seg.mode, frfr_unw, e, df, du, u_applied);

            pause(seg.Ts);
        end

        seg_t1 = seconds(datetime('now') - t_run_start);
        segmap(end+1) = struct('name',seg.name, 'mode',seg.mode, ...
            't_start',seg_t0, 't_end',seg_t1, 'Ts',seg.Ts, 'nOS',seg.nOS, ...
            'deadband',seg.deadband, 'du_max',seg.du_max); %#ok<AGROW>
    end
    fprintf("\n=== シーケンス 終了 ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    log_name = sprintf('frfr_phase2_seq_%s%s.csv', ts, tag);
    seg_name = sprintf('frfr_phase2_seq_%s%s_segmap.csv', ts, tag);

    writetable(table(L.t(:), L.seg(:), L.mode(:), L.dt(:), L.raw(:), L.unw(:), ...
        L.e(:), L.df(:), L.du(:), L.ao0(:), 'VariableNames', ...
        {'time_s','segment','mode','dt_actual_s','frfr_raw_ns','frfr_unwrapped_ns', ...
         'e_phase_ns','freq_err_ns_per_s','delta_u_V','ao0_V'}), log_name);
    fprintf("ログ保存: %s\n", log_name);

    smt = struct2table(segmap);
    smt.abs_start = string(datestr(t_run_start + seconds([segmap.t_start]'), 'HH:MM:SS'));
    writetable(smt, seg_name);
    fprintf("区間時刻表: %s\n", seg_name);

    %% === 区間サマリ（解析前の速報）====================================
    fprintf("\n--- 区間サマリ（終端60sのstd と FB電圧移動量）---\n");
    for k = 1:numel(segmap)
        sm = segmap(k);
        idx = (L.t > sm.t_end - 60) & (L.t <= sm.t_end);
        if sum(idx) > 5
            s_std = std(L.unw(idx));
            if strcmp(sm.mode,'FB')
                idx_all = (L.t >= sm.t_start) & (L.t <= sm.t_end);
                travel = sum(abs(L.du(idx_all)));
                fprintf("%-7s [FB]   std=%.3f ns | 電圧移動量=%.4f V\n", sm.name, s_std, travel);
            else
                fprintf("%-7s [HOLD] std=%.3f ns\n", sm.name, s_std);
            end
        end
    end

    %% === プロット ======================================================
    fig = figure('Name','sequence: FRFR','NumberTitle','off');
    plot(L.t, L.unw, 'b-', 'LineWidth', 1.0); hold on;
    if ~isnan(target_adjusted)
        yline(target_adjusted, 'r--', sprintf('Target %.1f', target_adjusted));
    end
    for k = 1:numel(segmap)
        xline(segmap(k).t_start, 'k:');
        text(segmap(k).t_start, max(L.unw,[],'omitnan'), ...
            sprintf(' %s', segmap(k).name), 'Rotation',90, 'VerticalAlignment','top', 'FontSize',8);
    end
    grid on; xlabel('Time [s]'); ylabel('FRFR (unwrapped) [ns]');
    title('一気通貫シーケンス FRFR');
    exportgraphics(fig, sprintf('frfr_phase2_seq_frfr_%s%s.pdf', ts, tag), 'ContentType','vector');

    %% === 結果 ==========================================================
    result = struct('log_csv',log_name, 'segmap_csv',seg_name, ...
        'target_adjusted',target_adjusted, 'segmap',segmap, ...
        't_run_start',t_run_start, 'opts',opts);
    fprintf("\n解析: segmap の t_start/t_end に「録音開始との時刻差」を足して WAV 窓を決め、\n");
    fprintf("      eval_jitter_260604_v0 に渡す。各 FB を HOLD1/HOLD2 と比較。\n");
end

%% === ヘルパー =========================================================
function seg = mkseg(name, mode, dur, Ts, nOS, deadband, du_max)
    seg = struct('name',name, 'mode',mode, 'dur',dur, 'Ts',Ts, ...
                 'nOS',nOS, 'deadband',deadband, 'du_max',du_max);
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
