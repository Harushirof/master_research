%% 初期化とパラメータ定義
clear; clc; close all;

% グローバル変数の定義（記事の構成準拠）
% ※大規模開発ではglobalの使用は推奨されませんが、今回は学習用コードとしてそのまま使用します
global A B 

% システム行列 A, 入力行列 B の定義
% x = [車両1位置; 車両1速度; 車両2位置; 車両2速度]
A = [0 1 0 0;
     0 0 0 0;
     0 0 0 1;
     0 0 0 0];

B = [0 0;
     1 0;
     0 0;
     0 1];

%% 可制御性の確認
Vo = [B, A*B, A^2*B, A^3*B];
rank_Vo = rank(Vo);
fprintf('可制御性行列のランク: %d (システム次数: 4)\n', rank_Vo);

if rank_Vo == 4
    disp('システムは可制御です。');
else
    disp('システムは可制御ではありません。');
end

%% シミュレーションの実行
% 初期値 x_syoki = [車両1位置; 車両1速度; 車両2位置; 車両2速度]
x_syoki = [5; 9; 0; 0]; 

% ode45（ルンゲ・クッタ法）による数値積分
% 0秒から10秒まで、0.01秒刻み
[t, x] = ode45(@main, 0:0.01:10, x_syoki);

%% 結果の描画

% Figure 1: 位置の推移
figure(1);
plot(t, x(:,1), 'b-', 'LineWidth', 2); hold on;
plot(t, x(:,3), 'r--', 'LineWidth', 2);
xlabel('Time [s]'); ylabel('Position [m]');
legend('Vehicle 1 (Leading)', 'Vehicle 2 (Following)');
title('車両位置の推移');
grid on;

% Figure 2: 速度の推移
figure(2);
plot(t, x(:,2), 'b-', 'LineWidth', 2); hold on;
plot(t, x(:,4), 'r--', 'LineWidth', 2);
xlabel('Time [s]'); ylabel('Velocity [m/s]');
legend('Vehicle 1', 'Vehicle 2');
title('車両速度の推移');
grid on;

% Figure 3: 車間距離の推移
figure(3);
% 車両1(先行) - 車両2(後続)
dist = x(:,1) - x(:,3);
plot(t, dist, 'k-', 'LineWidth', 2);
yline(5, 'r:', 'Target Distance'); % 目標車間距離の補助線
xlabel('Time [s]'); ylabel('Distance [m]');
title('車間距離の推移');
grid on;

%% 状態方程式と制御則を記述するローカル関数
function xd = main(t, x)
    global A B
    
    % 目標値の設定
    % v_r = 10 (目標速度)
    % d = -5 (相対距離目標。x1 - x3 = 5 となるように、相対位置 x3-x1 = -5 を目指す設定)
    
    % 状態フィードバックゲイン行列 K とフィードフォワード項を含む入力 u の計算
    % u = -Kx + Ref の形式になっています
    % 行列 [0 -1 0 0; 1 1 -1 -1] がフィードバックゲインに相当
    u = [0 -1 0 0; 1 1 -1 -1] * x + [10; -5];
    
    % 状態方程式 dx/dt = Ax + Bu
    ax = A * x + B * u;
    
    % 微分値（次のステップの状態）を返す
    xd = zeros(4,1);
    xd(1) = ax(1);
    xd(2) = ax(2);
    xd(3) = ax(3);
    xd(4) = ax(4);
end