import 'package:flutter/foundation.dart';
import '../tokens/token_portfolio.dart';
import '../../core/wallet.dart';

class WalletController extends ChangeNotifier {
  final WalletStore store;
  final TokenPortfolio tokens;
  final ChainService Function(Chain) serviceFactory;
  WalletController(
    this.store, {
    TokenPortfolio? tokens,
    ChainService Function(Chain)? serviceFactory,
  }) : tokens = tokens ?? TokenPortfolio(),
       serviceFactory = serviceFactory ?? ChainService.new;
  List<Account> accounts = [];
  Account? selected;
  Chain chain = Chain.all.first;
  int page = 0, epoch = 0;
  BigInt? balance;
  TronResources? resources;
  String? resourcesError;
  bool resourcesLoading = false;
  bool assetsLoading = false;
  int _assetsEpoch = 0, _resourcesEpoch = 0;
  bool historyLoading = false;
  int _historyEpoch = 0;
  List<Map<String, dynamic>> transactions = [];
  final Map<String, List<Map<String, dynamic>>> _submitted = {};
  String _historyKey(Chain network, Account account) =>
      '${network.id}:${account.address}';
  List<Map<String, dynamic>> _mergeSubmitted(
    Chain network,
    Account account,
    List<Map<String, dynamic>> result,
  ) {
    final pending = _submitted[_historyKey(network, account)] ?? [];
    final hashes = result.map((t) => t['hash']).toSet();
    pending.removeWhere((t) => hashes.contains(t['hash']));
    return [...pending.reversed, ...result];
  }

  void recordBroadcast(
    Chain network,
    Account account,
    Map<String, dynamic> transaction,
  ) {
    final pending = _submitted.putIfAbsent(
      _historyKey(network, account),
      () => [],
    );
    if (!pending.any((t) => t['hash'] == transaction['hash'])) {
      pending.add(transaction);
    }
    if (chain.id == network.id && selected?.address == account.address) {
      update(
        () => transactions = _mergeSubmitted(
          network,
          account,
          transactions.where((t) => t['pending'] != true).toList(),
        ),
      );
    }
  }

  String? balanceError, historyError, startupError;
  bool loading = false, booting = true, hidden = false;
  bool hideSmallTransactions = true;
  List<Map<String, dynamic>> get visibleTransactions => transactions.where((t) {
    if (!hideSmallTransactions || t['pending'] == true) return true;
    final amount = t['amount']?.toString();
    // Keep records whose amount is unknown; never classify contracts as dust.
    if (amount == null || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(amount)) {
      return true;
    }
    return BigInt.parse(amount.split('.').first).abs() >= BigInt.one;
  }).toList();
  void setHideSmallTransactions(bool value) =>
      update(() => hideSmallTransactions = value);
  bool _disposed = false;
  void update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void setPage(int value) => update(() => page = value);
  void toggleHidden() => update(() => hidden = !hidden);
  Future<void> renameAccount(Account account, String name) async {
    final label = name.trim();
    if (label.isEmpty) throw const FormatException('请输入钱包名称');
    final index = accounts.indexWhere(
      (a) =>
          a.family == account.family &&
          a.address == account.address &&
          a.chainId == account.chainId,
    );
    if (index < 0) throw StateError('钱包不存在');
    final current = accounts[index];
    final renamed = Account(
      label,
      current.address,
      current.signing,
      current.family,
      chainId: current.chainId,
    );
    final updated = [...accounts]..[index] = renamed;
    await store.save(updated);
    update(() {
      accounts = updated;
      if (selected?.family == current.family &&
          selected?.address == current.address &&
          selected?.chainId == current.chainId) {
        selected = renamed;
      }
    });
  }

  void selectAccount(Account account) {
    update(() {
      selected = account;
      if (!account.supportsChain(chain)) {
        chain = account.preferredChain;
      }
      page = 0;
    });
    refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    tokens.dispose();
    epoch++;
    super.dispose();
  }

  Future<void> load() async {
    try {
      final loaded = await store.load();
      if (_disposed) return;
      update(() {
        accounts = loaded;
        selected = loaded.firstOrNull;
        booting = false;
        if (selected != null) {
          chain = selected!.preferredChain;
        }
      });
      await refresh();
    } catch (_) {
      if (!_disposed) {
        update(() {
          booting = false;
          startupError = '无法读取 macOS 钥匙串，请检查系统访问权限后重试。';
        });
      }
    }
  }

  Future<void> refreshHistory() async {
    if (_disposed) return;
    final request = ++_historyEpoch;
    final account = selected;
    final network = chain;
    if (account == null) {
      update(() {
        transactions = [];
        historyError = null;
        historyLoading = false;
      });
      return;
    }
    update(() {
      historyLoading = true;
      historyError = null;
    });
    final service = serviceFactory(network);
    bool current() => !_disposed && request == _historyEpoch;
    try {
      final result = await service.history(account.address);
      if (current()) {
        update(() => transactions = _mergeSubmitted(network, account, result));
      }
    } catch (error) {
      if (current()) {
        update(
          () => historyError = network.id == 56
              ? 'BNB 交易记录请在区块浏览器查看。'
              : error is StateError
              ? error.message.toString()
              : '交易记录服务暂不可用，请检查网络后重试。',
        );
      }
    } finally {
      service.dispose();
      if (current()) update(() => historyLoading = false);
    }
  }

  Future<void> refreshAssets() async {
    if (_disposed) return;
    final request = ++_assetsEpoch;
    final account = selected, network = chain;
    bool current() => !_disposed && request == _assetsEpoch;
    update(() {
      assetsLoading = account != null;
      balanceError = null;
    });
    final tokenRequest = tokens.refresh(network, account?.address);
    if (account == null) {
      update(() => balance = null);
      await tokenRequest;
      return;
    }
    final service = serviceFactory(network);
    try {
      await Future.wait([
        tokenRequest,
        (() async {
          try {
            final result = await service.balance(account.address);
            if (current()) update(() => balance = result);
          } catch (error) {
            if (current()) {
              update(
                () => balanceError = error is StateError
                    ? error.message.toString()
                    : '余额查询失败，请重试',
              );
            }
          }
        })(),
      ]);
    } finally {
      service.dispose();
      if (current()) update(() => assetsLoading = false);
    }
  }

  Future<void> refreshResources() async {
    if (_disposed) return;
    final request = ++_resourcesEpoch;
    final account = selected, network = chain;
    bool current() => !_disposed && request == _resourcesEpoch;
    if (account == null || network.family != Family.tron) {
      update(() {
        resources = null;
        resourcesError = null;
        resourcesLoading = false;
      });
      return;
    }
    update(() {
      resourcesLoading = true;
      resourcesError = null;
    });
    final service = serviceFactory(network);
    try {
      final result = await service.resources(account.address);
      if (current()) update(() => resources = result);
    } catch (error) {
      if (current()) {
        update(
          () => resourcesError = error is StateError
              ? error.message.toString()
              : '资源查询失败，请重试',
        );
      }
    } finally {
      service.dispose();
      if (current()) update(() => resourcesLoading = false);
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final request = ++epoch;
    update(() {
      loading = true;
      balance = null;
      resources = null;
      transactions = selected == null
          ? []
          : _mergeSubmitted(chain, selected!, []);
    });
    await Future.wait([refreshAssets(), refreshResources(), refreshHistory()]);
    if (!_disposed && request == epoch) update(() => loading = false);
  }

  void selectChain(Chain c) {
    tokens.clear();
    update(() {
      chain = c;
      selected = accounts.where((a) => a.supportsChain(c)).firstOrNull;
      balance = null;
      resources = null;
      resourcesError = null;
      resourcesLoading = false;
      transactions = [];
      balanceError = historyError = null;
      epoch++;
      loading = false;
    });
    refresh();
  }
}
