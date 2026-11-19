import 'package:flutter/foundation.dart';
import '../tokens/token_portfolio.dart';
import '../../core/wallet.dart';
import '../../core/token.dart';

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
  final Map<String, _WalletCache> _cache = {};
  final Map<String, Future<void>> _initialLoads = {};
  _WalletCache _entry(Chain network, Account account) =>
      _cache.putIfAbsent(_historyKey(network, account), _WalletCache.new);

  Future<void> showWallet() async {
    if (_disposed) return;
    final account = selected;
    final network = chain;
    final key = account == null ? null : _historyKey(network, account);
    ++epoch;
    void restore() {
      final saved = account == null ? null : _cache[key];
      update(() {
        balance = saved?.balance;
        balanceError = saved?.balanceError;
        resources = saved?.resources;
        resourcesError = saved?.resourcesError;
        transactions = account == null
            ? []
            : _mergeSubmitted(network, account, saved?.transactions ?? []);
        historyError = saved?.historyError;
        historyPage = 0;
        historyHasMore = saved?.historyCursor != null;
        loading = assetsLoading = resourcesLoading = historyLoading = false;
      });
      tokens.restore(network, account?.address);
    }

    restore();
    if (key == null) return;
    final pending = _initialLoads[key];
    if (pending != null) {
      await pending;
      if (!_disposed &&
          chain.id == network.id &&
          selected?.address == account!.address) {
        restore();
      }
      return;
    }
    // Retain the completed future as the session's first-load marker.
    final request = refresh();
    _initialLoads[key] = request;
    await request;
  }

  List<Account> accounts = [];
  Account? selected;
  Chain chain = Chain.all.first;
  int page = 0, epoch = 0;
  bool? governanceVote;

  void openGovernance({required bool vote}) {
    if (chain.family != Family.tron || selected == null) return;
    update(() {
      page = 0;
      governanceVote = vote;
    });
  }

  void closeGovernance() {
    update(() => governanceVote = null);
    showWallet();
  }

  BigInt? balance;
  TronResources? resources;
  String? resourcesError;
  bool resourcesLoading = false;
  bool assetsLoading = false;
  bool historyLoading = false;
  static const historyPageSize = 7;
  int historyPage = 0;
  bool historyHasMore = false;
  List<Map<String, dynamic>> get pagedTransactions => visibleTransactions
      .skip(historyPage * historyPageSize)
      .take(historyPageSize)
      .toList();
  bool get canGoForwardHistory =>
      (historyPage + 1) * historyPageSize < visibleTransactions.length ||
      historyHasMore;
  void previousHistoryPage() {
    if (!historyLoading && historyPage > 0) update(() => historyPage--);
  }

  Future<void> nextHistoryPage() async {
    if (historyLoading || !canGoForwardHistory) return;
    final account = selected;
    final network = chain;
    final filter = hideSmallTransactions;
    final target = historyPage + 1;
    var batches = 0;
    while (historyHasMore &&
        visibleTransactions.length < (target + 1) * historyPageSize &&
        batches++ < 5) {
      await _fetchHistory(append: true);
      if (_disposed ||
          selected != account ||
          chain.id != network.id ||
          historyError != null ||
          hideSmallTransactions != filter) {
        return;
      }
    }
    if (visibleTransactions.length > target * historyPageSize) {
      update(() => historyPage = target);
    }
  }

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
  bool isAssetTransfer(Map<String, dynamic> t) {
    if (t['amount'] == null || t['incoming'] is! bool) return false;
    if (t['assetId'] != null) return false;
    final contract = t['tokenAddress'] as String?;
    if (contract == null) {
      return t['symbol'] == chain.symbol &&
          (t['detail'] == 'TransferContract' ||
              t['pending'] == true ||
              t['detail'] == '转账');
    }
    String normalized(String address) =>
        chain.family == Family.evm ? address.toLowerCase() : address;
    return [...presetTokens(chain), ...tokens.balances.map((b) => b.token)]
        .where((token) => token.chainId == chain.id)
        .any((token) => normalized(token.address) == normalized(contract));
  }

  List<Map<String, dynamic>> get visibleTransactions => transactions.where((t) {
    if (!isAssetTransfer(t)) return false;
    if (!hideSmallTransactions || t['pending'] == true) return true;
    final amount = t['amount']?.toString();
    // Keep records whose amount is unknown; never classify contracts as dust.
    if (amount == null || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(amount)) {
      return true;
    }
    return BigInt.parse(amount.split('.').first).abs() >= BigInt.one;
  }).toList();
  void setHideSmallTransactions(bool value) => update(() {
    hideSmallTransactions = value;
    historyPage = 0;
  });
  bool _disposed = false;
  void update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void setPage(int value) => update(() {
    page = value;
    governanceVote = null;
  });
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

  bool reorderingWallets = false;

  /// Reorder only visible chain slots; other networks retain their positions.
  Future<bool> reorderWallets(int oldIndex, int newIndex) async {
    if (reorderingWallets || _disposed) return false;
    final slots = <int>[
      for (var i = 0; i < accounts.length; i++)
        if (accounts[i].supportsChain(chain)) i,
    ];
    if (oldIndex < 0 ||
        oldIndex >= slots.length ||
        newIndex < 0 ||
        newIndex > slots.length) {
      return false;
    }
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return true;
    final before = accounts;
    final visible = slots.map((i) => before[i]).toList();
    visible.insert(newIndex, visible.removeAt(oldIndex));
    final updated = [...before];
    for (var i = 0; i < slots.length; i++) {
      updated[slots[i]] = visible[i];
    }
    update(() {
      accounts = updated;
      reorderingWallets = true;
    });
    try {
      await store.save(updated);
      return true;
    } catch (_) {
      if (!_disposed && identical(accounts, updated)) {
        update(() => accounts = before);
      }
      return false;
    } finally {
      if (!_disposed) update(() => reorderingWallets = false);
    }
  }

  Future<void> deleteAccount(Account account) async {
    await store.remove(account, accounts);
    if (_disposed) return;
    final deletingSelected =
        selected?.family == account.family &&
        selected?.address == account.address &&
        selected?.chainId == account.chainId;
    update(() {
      accounts = accounts
          .where(
            (a) =>
                !(a.family == account.family &&
                    a.address == account.address &&
                    a.chainId == account.chainId),
          )
          .toList();
      for (final network in Chain.all.where(
        (c) => c.family == account.family,
      )) {
        final key = _historyKey(network, account);
        _cache.remove(key);
        _initialLoads.remove(key);
        _submitted.remove(key);
      }
      tokens.forget(account.address);
      if (deletingSelected) {
        selected =
            accounts.where((a) => a.supportsChain(chain)).firstOrNull ??
            accounts.firstOrNull;
        if (selected != null && !selected!.supportsChain(chain)) {
          chain = selected!.preferredChain;
        }
      }
    });
    if (deletingSelected) await showWallet();
  }

  void selectAccount(Account account) {
    update(() {
      selected = account;
      if (!account.supportsChain(chain)) {
        chain = account.preferredChain;
      }
      page = 0;
      if (chain.family != Family.tron) governanceVote = null;
    });
    showWallet();
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
      await showWallet();
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
    final account = selected;
    final network = chain;
    await _fetchHistory();
    var batches = 0;
    while (!_disposed &&
        selected == account &&
        chain.id == network.id &&
        historyError == null &&
        historyHasMore &&
        visibleTransactions.length < historyPageSize &&
        batches++ < 5) {
      await _fetchHistory(append: true);
    }
  }

  Future<void> _fetchHistory({bool append = false}) async {
    if (_disposed) return;
    final account = selected;
    final network = chain;
    if (account == null) {
      update(() {
        transactions = [];
        historyPage = 0;
        historyHasMore = false;
        historyError = null;
        historyLoading = false;
      });
      return;
    }
    _entry(network, account).historyError = null;
    update(() {
      historyLoading = true;
      historyError = null;
      if (!append) historyPage = 0;
    });
    final service = serviceFactory(network)
      ..paginateHistory = true
      ..historyCursor = append ? _entry(network, account).historyCursor : null;
    final revision = ++_entry(network, account).historyRevision;
    bool valid() =>
        !_disposed && _entry(network, account).historyRevision == revision;
    bool current() =>
        valid() &&
        chain.id == network.id &&
        selected?.address == account.address;
    try {
      if (network.family == Family.tron) {
        final custom = await tokens.repository.load();
        if (_disposed) return;
        service.historyTokenContracts = {
          for (final token in [...presetTokens(network), ...custom])
            if (token.chainId == network.id) token.address,
        };
      }
      final result = await service.history(account.address);
      final combined = append
          ? [..._entry(network, account).transactions, ...result]
          : result;
      if (valid()) {
        _entry(network, account).transactions = List.of(combined);
        _entry(network, account).historyCursor = service.nextHistoryCursor;
      }
      if (current()) {
        update(() {
          transactions = _mergeSubmitted(network, account, combined);
          historyHasMore = service.nextHistoryCursor != null;
        });
      }
    } catch (error) {
      if (valid()) {
        _entry(network, account).historyError = error is StateError
            ? error.message.toString()
            : '交易记录查询失败，请重试';
      }
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
    final account = selected, network = chain;
    final revision = account == null
        ? 0
        : ++_entry(network, account).assetsRevision;
    bool valid() =>
        !_disposed &&
        account != null &&
        _entry(network, account).assetsRevision == revision;
    bool current() =>
        valid() &&
        chain.id == network.id &&
        selected?.address == account?.address;
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
    _entry(network, account).balanceError = null;
    final service = serviceFactory(network);
    try {
      await Future.wait([
        tokenRequest,
        (() async {
          try {
            final result = await service.balance(account.address);
            if (valid()) _entry(network, account).balance = result;
            if (current()) update(() => balance = result);
          } catch (error) {
            if (valid()) {
              _entry(network, account).balanceError = error is StateError
                  ? error.message.toString()
                  : '余额查询失败，请重试';
            }
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
    final account = selected, network = chain;
    final revision = account == null
        ? 0
        : ++_entry(network, account).resourcesRevision;
    bool valid() =>
        !_disposed &&
        account != null &&
        _entry(network, account).resourcesRevision == revision;
    bool current() =>
        valid() &&
        chain.id == network.id &&
        selected?.address == account?.address;
    if (account == null || network.family != Family.tron) {
      update(() {
        resources = null;
        resourcesError = null;
        resourcesLoading = false;
      });
      return;
    }
    _entry(network, account).resourcesError = null;
    update(() {
      resourcesLoading = true;
      resourcesError = null;
    });
    final service = serviceFactory(network);
    try {
      final result = await service.resources(account.address);
      if (valid()) _entry(network, account).resources = result;
      if (current()) update(() => resources = result);
    } catch (error) {
      if (valid()) {
        _entry(network, account).resourcesError = error is StateError
            ? error.message.toString()
            : '资源查询失败，请重试';
      }
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
      governanceVote = null;
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
    showWallet();
  }
}

class _WalletCache {
  int historyRevision = 0, assetsRevision = 0, resourcesRevision = 0;
  BigInt? balance;
  TronResources? resources;
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic>? historyCursor;
  String? balanceError, resourcesError, historyError;
}
