import 'package:flutter/foundation.dart';
import '../../core/models.dart';
import '../../core/token.dart';
import '../../core/token_service.dart';
import '../../core/token_repository.dart';
import '../../core/chain_service.dart';

class TokenPortfolio extends ChangeNotifier {
  final TokenRepository repository;
  final ChainService Function(Chain) serviceFactory;
  TokenPortfolio({
    TokenRepository? repository,
    ChainService Function(Chain)? serviceFactory,
  }) : repository = repository ?? TokenRepository(),
       serviceFactory = serviceFactory ?? ((chain) => ChainService(chain));
  List<TokenBalance> balances = [];
  String? configurationError;
  bool loading = false, _disposed = false;
  int _epoch = 0;
  Chain? _chain;
  String? _owner;
  final Map<String, (List<TokenBalance>, String?)> _cache = {};
  final Map<String, int> _latest = {};
  String _key(Chain chain, String owner) => '${chain.id}:$owner';
  void forget(String address) {
    _cache.removeWhere((key, _) => key.endsWith(':$address'));
    _latest.removeWhere((key, _) => key.endsWith(':$address'));
  }

  void restore(Chain chain, String? owner) {
    _epoch++;
    _chain = chain;
    _owner = owner;
    final saved = owner == null ? null : _cache[_key(chain, owner)];
    balances = saved == null ? [] : List.of(saved.$1);
    configurationError = saved?.$2;
    loading = false;
    if (!_disposed) notifyListeners();
  }

  void clear() {
    _epoch++;
    balances = [];
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh(Chain chain, String? owner) async {
    final epoch = ++_epoch;
    if (owner != null) _latest[_key(chain, owner)] = epoch;
    _chain = chain;
    _owner = owner;
    balances = presetTokens(chain).map((t) => TokenBalance(t)).toList();
    loading = owner != null;
    configurationError = null;
    if (!_disposed) notifyListeners();
    String? queryError;
    var definitions = presetTokens(chain);
    try {
      final custom = await repository.load();
      if (_disposed) return;
      final known = definitions.map((t) => t.id).toSet();
      definitions = [
        ...definitions,
        ...custom.where((t) => t.chainId == chain.id && known.add(t.id)),
      ];
    } catch (_) {
      queryError = '自定义代币配置读取失败，请重试';
    }
    if (_disposed) return;
    final result = definitions.map((t) => TokenBalance(t)).toList();
    void publish({bool done = false}) {
      if (_disposed ||
          (owner != null && _latest[_key(chain, owner)] != epoch)) {
        return;
      }
      if (owner != null) {
        _cache[_key(chain, owner)] = (List.of(result), queryError);
      }
      if (_chain?.id == chain.id && _owner == owner) {
        balances = List.of(result);
        configurationError = queryError;
        loading = !done;
        notifyListeners();
      }
    }

    publish();
    if (owner == null) {
      publish(done: true);
      return;
    }
    final service = serviceFactory(chain);
    try {
      for (var i = 0; i < definitions.length; i++) {
        if (_disposed) return;
        final token = definitions[i];
        try {
          final amount = await TokenService(service).balance(token, owner);
          result[i] = TokenBalance(token, amount: amount);
        } catch (error) {
          result[i] = TokenBalance(
            token,
            error: error is StateError
                ? error.message.toString()
                : '查询失败，请检查网络后重试',
          );
        }
        publish();
      }
    } finally {
      service.dispose();
      publish(done: true);
    }
  }

  Future<void> add(TokenDefinition token) async {
    final chain = Chain.all.firstWhere((c) => c.id == token.chainId);
    final custom = await repository.load();
    if ([...presetTokens(chain), ...custom].any((t) => t.id == token.id)) {
      throw StateError('此代币已在列表中');
    }
    await repository.save([...custom, token]);
    if (!_disposed && _chain != null) await refresh(_chain!, _owner);
  }

  Future<void> remove(TokenDefinition token) async {
    if (!token.custom) return;
    final custom = await repository.load();
    await repository.save(custom.where((t) => t.id != token.id).toList());
    if (!_disposed && _chain != null) await refresh(_chain!, _owner);
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
