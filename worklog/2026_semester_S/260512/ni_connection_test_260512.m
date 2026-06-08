function result = ni_connection_test_260512()
%====================================================================
% NI DAQ 接続テスト
%
% NI USB-6211 (Dev1) の接続状況を段階的に確認する診断スクリプト。
% 各ステップは try/catch で囲んであり、途中で失敗しても次のチェックに
% 進む。最後に PASS/FAIL のサマリを表示する。
%
% 使い方:
%   ni_connection_test_260512()
%
% チェック項目:
%   1. daqlist("ni") で NI デバイスを列挙
%   2. Dev1 のモデル名・シリアル・チャネル一覧を表示
%   3. ao0 / ao1 を持つセッション作成
%   4. ao0=0V, ao1=0V を実書き込み（疎通テスト、安全側）
%   5. セッション release
%
% 安全装置:
%   - 出力は 0V のみ（OCXO 周波数を動かさない）
%   - onCleanup で異常時も release を保証
%====================================================================

    fprintf("\n========== NI DAQ 接続テスト (%s) ==========\n", ...
        string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

    result = struct( ...
        'step1_daqlist',   false, ...
        'step2_device',    false, ...
        'step3_session',   false, ...
        'step4_write',     false, ...
        'step5_release',   false, ...
        'device_info',     [], ...
        'error_msgs',      {{}});

    s = [];
    cleanupObj = onCleanup(@() safeCleanup(s)); %#ok<NASGU>

    %% === Step 1: デバイス列挙 =========================================
    fprintf("\n[1/5] daqlist(""ni"") でデバイスを列挙...\n");
    try
        dlist = daqlist("ni");
        disp(dlist);
        if isempty(dlist)
            error("NI デバイスが見つかりません。MAX (NI-MAX) で Dev1 が認識されているか確認してください。");
        end
        result.step1_daqlist = true;
        fprintf("  -> OK: %d 台検出\n", height(dlist));
    catch ME
        fprintf(2, "  -> NG: %s\n", ME.message);
        result.error_msgs{end+1} = sprintf("[Step1] %s", ME.message);
        fprintf("\n停止: デバイスが見つからないため後続テストはスキップします。\n");
        printSummary(result);
        return;
    end

    %% === Step 2: デバイス詳細 =========================================
    fprintf("\n[2/5] Dev1 の詳細情報...\n");
    try
        idxDev1 = find(strcmp(string(dlist.DeviceID), "Dev1"), 1);
        if isempty(idxDev1)
            error("Dev1 が見つかりません（検出: %s）", strjoin(string(dlist.DeviceID), ", "));
        end
        devInfo = dlist.DeviceInfo(idxDev1);

        % プロパティを防御的に取得（MATLAB / DAQ Toolbox のバージョン差吸収）
        printIfHas(devInfo, "Model",        "  Model    : %s\n");
        printIfHas(devInfo, "Vendor",       "  Vendor   : %s\n");
        printIfHas(devInfo, "SerialNumber", "  Serial   : %s\n");
        printIfHas(devInfo, "ID",           "  ID       : %s\n");

        % チャネル一覧（プロパティ名は環境により Channels / Subsystems 等あり得る）
        chNames = strings(0);
        if isprop(devInfo, 'Channels') && ~isempty(devInfo.Channels)
            try
                chNames = string({devInfo.Channels.ID});
            catch
                try, chNames = string({devInfo.Channels.Name}); catch, end
            end
            fprintf("  Channels : %d 個\n", numel(devInfo.Channels));
        elseif isprop(devInfo, 'Subsystems')
            fprintf("  Subsystems: %d 個（Channels プロパティ無し）\n", ...
                numel(devInfo.Subsystems));
            try
                for kk = 1:numel(devInfo.Subsystems)
                    sub = devInfo.Subsystems(kk);
                    if isprop(sub, 'ChannelNames')
                        chNames = [chNames, string(sub.ChannelNames)]; %#ok<AGROW>
                    end
                end
            catch
            end
        end

        if ~isempty(chNames)
            fprintf("  チャネル例: %s\n", strjoin(chNames(1:min(end,8)), ", "));
            hasAO0 = any(contains(chNames, "ao0"));
            hasAO1 = any(contains(chNames, "ao1"));
            fprintf("    ao0 存在: %s\n", ternary(hasAO0, "OK", "NG"));
            fprintf("    ao1 存在: %s\n", ternary(hasAO1, "OK", "NG"));
        else
            % チャネル列挙に失敗しても Step3 のセッション作成で実体確認するので継続
            fprintf("  ※ チャネル列挙はスキップ（Step3 で実体確認します）\n");
        end

        result.device_info = devInfo;
        result.step2_device = true;
        fprintf("  -> OK\n");
    catch ME
        fprintf(2, "  -> NG: %s\n", ME.message);
        result.error_msgs{end+1} = sprintf("[Step2] %s", ME.message);
        fprintf("  ※ Step2 失敗だが Step3 以降は試行します\n");
    end

    %% === Step 3: セッション作成 =======================================
    fprintf("\n[3/5] セッション作成 + ao0/ao1 追加...\n");
    try
        s = daq.createSession('ni');
        addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
        addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');
        fprintf("  Session Rate : %.0f Hz\n", s.Rate);
        fprintf("  Channels     : %d\n", numel(s.Channels));
        result.step3_session = true;
        fprintf("  -> OK\n");
    catch ME
        fprintf(2, "  -> NG: %s\n", ME.message);
        result.error_msgs{end+1} = sprintf("[Step3] %s", ME.message);
        printSummary(result);
        return;
    end

    %% === Step 4: 0V 書き込みテスト ====================================
    fprintf("\n[4/5] 0V 書き込みテスト (ao0=0V, ao1=0V)...\n");
    try
        outputSingleScan(s, [0, 0]);
        pause(0.2);
        outputSingleScan(s, [0, 0]);   % 念のため再度0V
        result.step4_write = true;
        fprintf("  -> OK: 書き込み成功\n");
    catch ME
        fprintf(2, "  -> NG: %s\n", ME.message);
        result.error_msgs{end+1} = sprintf("[Step4] %s", ME.message);
        printSummary(result);
        return;
    end

    %% === Step 5: release =============================================
    fprintf("\n[5/5] セッション release...\n");
    try
        release(s);
        s = [];
        result.step5_release = true;
        fprintf("  -> OK\n");
    catch ME
        fprintf(2, "  -> NG: %s\n", ME.message);
        result.error_msgs{end+1} = sprintf("[Step5] %s", ME.message);
    end

    %% === サマリ ======================================================
    printSummary(result);
end

%% ====================================================================
%% ヘルパー関数
%% ====================================================================
function printSummary(result)
    fprintf("\n========== サマリ ==========\n");
    steps = {'step1_daqlist', 'step2_device', 'step3_session', ...
             'step4_write',   'step5_release'};
    labels = {'1. daqlist',     '2. device info', '3. session', ...
              '4. write 0V',    '5. release'};
    nPass = 0;
    for k = 1:numel(steps)
        ok = result.(steps{k});
        if ok, nPass = nPass + 1; end
        fprintf("  [%s] %s\n", ternary(ok, "PASS", "FAIL"), labels{k});
    end
    fprintf("----------------------------\n");
    fprintf("結果: %d / %d PASS\n", nPass, numel(steps));
    if ~isempty(result.error_msgs)
        fprintf("\nエラー一覧:\n");
        for k = 1:numel(result.error_msgs)
            fprintf("  - %s\n", result.error_msgs{k});
        end
    end
    fprintf("============================\n\n");
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function printIfHas(obj, propName, fmt)
    % 指定プロパティが存在し空でなければフォーマット出力。無ければ無視。
    try
        if isprop(obj, propName) || isfield(obj, propName)
            val = obj.(propName);
            if isempty(val), return; end
            if isstruct(val) || isobject(val)
                % Vendor などはオブジェクト/構造体 -> ID か Name を試す
                try
                    if isprop(val, 'ID') || isfield(val, 'ID')
                        val = val.ID;
                    elseif isprop(val, 'Name') || isfield(val, 'Name')
                        val = val.Name;
                    else
                        val = class(val);
                    end
                catch
                    val = class(val);
                end
            end
            fprintf(fmt, string(val));
        end
    catch
        % 取得失敗は静かに無視
    end
end

function safeCleanup(s)
    if isempty(s), return; end
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
end
