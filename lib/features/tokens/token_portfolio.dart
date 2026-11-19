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
  void clear() {
    _epoch++;
    balances = [];
    loading = false;
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> refresh(Chain chain, String? owner) async {
    final epoch = ++_epoch;
    _chain = chain;
    _owner = owner;
    balances = presetTokens(chain).map((t) => TokenBalance(t)).toList();
    loading = owner != null;
    configurationError = null;
    if (!_disposed) notifyListeners();
    var definitions = presetTokens(chain);
    try {
      final custom = await repository.load();
      if (!_current(epoch)) return;
      final known = definitions.map((t) => t.id).toSet();
      definitions = [
        ...definitions,
        ...custom.where((t) => t.chainId == chain.id && known.add(t.id)),
      ];
    } catch (_) {
      if (_current(epoch)) configurationError = '自定义代币配置读取失败，请重试';
    }
    if (!_current(epoch)) return;
    balances = definitions.map((t) => TokenBalance(t)).toList();
    notifyListeners();
    if (owner == null) {
      loading = false;
      notifyListeners();
      return;
    }
    final service = serviceFactory(chain);
    try {
      // Sequential requests avoid bursts against public nodes, notably TronGrid.
      for (var i = 0; i < definitions.length; i++) {
        if (!_current(epoch)) return;
        final token = definitions[i];
        try {
          final amount = await TokenService(service).balance(token, owner);
          if (!_current(epoch)) return;
          balances[i] = TokenBalance(token, amount: amount);
        } catch (error) {
          if (!_current(epoch)) return;
          balances[i] = TokenBalance(
            token,
            error: error is StateError
                ? error.message.toString()
                : '查询失败，请检查网络后重试',
          );
        }
        notifyListeners();
      }
    } finally {
      service.dispose();
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
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
