import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/market_chart.dart';
import '../../core/models.dart';
import '../../core/token.dart';
import '../../shared/widgets/back_to_assets_button.dart';

class MarketChartPage extends StatefulWidget {
  final Chain chain;
  final TokenDefinition? token;
  final Uri? pageUrl;
  final String? pageTitle;
  const MarketChartPage({
    super.key,
    required this.chain,
    this.token,
    this.pageUrl,
    this.pageTitle,
  });
  @override
  State<MarketChartPage> createState() => _MarketChartPageState();
}

class _MarketChartPageState extends State<MarketChartPage> {
  late Future<Uri> request = (widget.pageUrl != null
      ? Future.value(widget.pageUrl!)
      : MarketChart.resolve(widget.chain, widget.token));
  int revision = 0;
  void reload() => setState(() {
    revision++;
    request = (widget.pageUrl != null
        ? Future.value(widget.pageUrl!)
        : MarketChart.resolve(widget.chain, widget.token));
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const BackToAssetsButton(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.pageTitle ??
                        '${widget.token?.symbol ?? widget.chain.symbol} · ${widget.chain.name} · K 线',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ShadButton.outline(onPressed: reload, child: const Text('刷新')),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Uri>(
              future: request,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error is FormatException
                              ? error.message
                              : '行情加载失败，请检查网络后重试',
                        ),
                        const SizedBox(height: 16),
                        ShadButton(onPressed: reload, child: const Text('重试')),
                      ],
                    ),
                  );
                }
                return AppKitView(
                  key: ValueKey(revision),
                  viewType: 'linkwallet/market-chart',
                  layoutDirection: TextDirection.ltr,
                  creationParams: {
                    'url': snapshot.data.toString(),
                    'dark': Theme.of(context).brightness == Brightness.dark,
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
