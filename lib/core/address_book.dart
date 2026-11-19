import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'address_codec.dart';

class AddressEntry {
  final String name, address;
  final int chainId;
  const AddressEntry(this.name, this.address, this.chainId);
  Chain get chain => Chain.all.firstWhere((c) => c.id == chainId);
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'chainId': chainId,
  };
  factory AddressEntry.fromJson(Map<String, dynamic> json) => AddressEntry(
    json['name'] as String,
    json['address'] as String,
    json['chainId'] as int,
  );
}

class AddressBookRepository {
  static const key = 'linkwallet.addressBook.v1';
  Future<List<AddressEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    final entries = (jsonDecode(raw) as List)
        .map((j) => AddressEntry.fromJson(j as Map<String, dynamic>))
        .toList();
    for (final entry in entries) {
      validateAddress(entry.address, entry.chain.family);
      if (entry.name.trim().isEmpty) throw const FormatException('地址名称不能为空');
    }
    return entries;
  }

  Future<void> save(List<AddressEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('无法保存地址本');
    }
  }
}
