function frfr_pulse_after_fb_sweep()
%==========================================================================
% Δv を複数試しながら、frfr_pulse_after_fb_single_run を順番に実行。
% 各 Run の間には「2 分のインターバル（電圧 0V）」を入れる。
%
% 出力：
%   ・各 Run のログ CSV
%   ・Sweep 全体のサマリ CSV
%   ・ΔFRFR と K のプロット
%==========================================================================

    %----------------------------------------
    % パルス幅は固定
    %----------------------------------------
    T_pulse = 1.0;  % [s]

    %----------------------------------------
    % Δv リスト（10 点）
    %----------------------------------------
    delta_v_list = [ ...
        0.01, 0.02, 0.05, 0.10, 0.20, ...
        0.30, 0.40, 0.50, 0.75, 1.00];

    num_runs = numel(delta_v_list);

    %----------------------------------------
    % 結果格納用
    %----------------------------------------
    delta_v_col      = zeros(num_runs,1);
    T_pulse_col      = zeros(num_runs,1);
    FRFR_before_col  = zeros(num_runs,1);
    FRFR_after_col   = zeros(num_runs,1);
    delta_FRFR_col   = zeros(num_runs,1);
    K_col            = zeros(num_runs,1);
    csv_name_col     = strings(num_runs,1);

    fprintf("\n================ Sweep 開始 ================\n");

    %======================================================================
    %                          メインループ
    %======================================================================
    for i = 1:num_runs
        dv = delta_v_list(i);

        fprintf("\n-------------------------------------------------------\n");
        fprintf(" Sweep Run %d / %d : Δv = %.4f V\n", i, num_runs, dv);
        fprintf("-------------------------------------------------------\n");

        %==================================================================
        % 1 回分のパルス実験を実行
        %==================================================================
        res = frfr_pulse_after_fb_single_run(dv, T_pulse);

        % 結果保存
        delta_v_col(i)     = res.delta_v;
        T_pulse_col(i)     = res.T_pulse;
        FRFR_before_col(i) = res.FRFR_before_mean;
        FRFR_after_col(i)  = res.FRFR_after_mean;
        delta_FRFR_col(i)  = res.delta_FRFR_ns;
        K_col(i)           = res.K_ns_per_Vs;
        csv_name_col(i)    = res.csv_name;

        %==================================================================
        % 次の Run の前に 2 分休憩（安全のため 0V に戻す）
        %==================================================================
        if i < num_runs
            fprintf(" Run %d 終了。次の Run まで 120 秒待機します...\n", i);

            % --- 念のため DAQ を 0V に戻す ---
            try
                s2 = daq.createSession('ni');
                addAnalogOutputChannel(s2,'Dev1','ao0','Voltage');
                addAnalogOutputChannel(s2,'Dev1','ao1','Voltage');
                outputSingleScan(s2, [0, 0]);
                release(s2);
            catch
                warning("DAQ を 0V に戻す処理に失敗しました");
            end

            pause(120);  % 2 分休む
        end
    end

    fprintf("\n================ Sweep 完了 ================\n");

    %======================================================================
    %                     Sweep サマリを CSV で保存
    %======================================================================
    summary_tbl = table( ...
        delta_v_col, ...
        T_pulse_col, ...
        FRFR_before_col, ...
        FRFR_after_col, ...
        delta_FRFR_col, ...
        K_col, ...
        csv_name_col, ...
        'VariableNames', ...
        {'delta_v_V','T_pulse_s','FRFR_before_ns','FRFR_after_ns', ...
         'delta_FRFR_ns','K_ns_per_Vs','log_csv_name'} ...
    );

    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    summary_name = sprintf('frfr_pulse_sweep_summary_%s.csv', timestamp);
    writetable(summary_tbl, summary_name);

    fprintf("Sweep サマリを保存しました: %s\n", summary_name);

    %======================================================================
    % プロット：ΔFRFR vs Δv、K vs Δv
    %======================================================================
    figure('Name','Sweep Results','NumberTitle','off');
    tiledlayout(2,1);

    nexttile(1);
    plot(delta_v_col, delta_FRFR_col, '-o', 'LineWidth',1.5);
    grid on;
    xlabel('\Delta v [V]');
    ylabel('\Delta FRFR [ns]');
    title('\Delta FRFR vs \Delta v');

    nexttile(2);
    plot(delta_v_col, K_col, '-o', 'LineWidth',1.5);
    grid on;
    xlabel('\Delta v [V]');
    ylabel('K [ns/(V·s)]');
    title('K vs \Delta v');

end
