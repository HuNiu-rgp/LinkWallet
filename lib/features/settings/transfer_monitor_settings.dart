import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../monitoring/wallet_transfer_monitor.dart';
import '../../shared/theme_context.dart';

class TransferMonitorSettings extends StatelessWidget {
  final WalletTransferMonitor monitor;
  const TransferMonitorSettings({super.key, required this.monitor});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) => ShadCard(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '钱包转账监控',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              ShadSwitch(
                value: monitor.enabled,
                onChanged: (value) => monitor.setEnabled(value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '每 60 秒检查所有已添加钱包及“我的资产”中的币种。TRON 通知已确认的收款和转账，其他网络通知余额增减。首次查询只建立基准，不发送旧记录通知。',
            style: TextStyle(
              color: context.palette.mutedForeground,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '窗口隐藏后继续运行；退出 App 或电脑休眠时停止。轮询可能延迟，短时间内的多笔交易或净余额不变的交易可能无法完整提醒。',
            style: TextStyle(
              fontSize: 12,
              color: context.palette.mutedForeground,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            !monitor.enabled
                ? '监控已关闭'
                : !monitor.permissionGranted
                ? '尚未获得系统通知权限，请在 macOS 系统设置 → 通知中允许 LinkWallet。'
                : monitor.checking
                ? '正在检查钱包…'
                : '监控已开启',
          ),
          if (monitor.lastChecked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '上次检查：${monitor.lastChecked.toString().split('.').first}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.mutedForeground,
                ),
              ),
            ),
          if (monitor.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                monitor.error!,
                style: TextStyle(color: context.palette.destructive),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton.outline(
                onPressed: monitor.enabled && monitor.permissionGranted
                    ? monitor.testNotification
                    : null,
                child: const Text('发送测试通知'),
              ),
              if (monitor.enabled && !monitor.permissionGranted)
                ShadButton.outline(
                  onPressed: () => monitor.setEnabled(true),
                  child: const Text('重新检查权限'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
