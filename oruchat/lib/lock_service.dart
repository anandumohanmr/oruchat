import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils.dart';

/// Chat lock: PIN ee phone-il mathram save aakum. Locked chats thurakkaan PIN venam.
class LockService extends ChangeNotifier {
  LockService._();
  static final LockService instance = LockService._();

  SharedPreferences? _p;
  Set<String> _locked = {};
  String? _hash;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    _locked = (_p!.getStringList('locked_chats') ?? <String>[]).toSet();
    _hash = _p!.getString('pin_hash');
    notifyListeners();
  }

  bool get hasPin => _hash != null;
  bool isLocked(String chatId) => _locked.contains(chatId);
  int get lockedCount => _locked.length;

  String _h(String pin) =>
      sha256.convert(utf8.encode('oruchat:$pin')).toString();

  bool verify(String pin) => _hash != null && _hash == _h(pin);

  Future<void> setPin(String pin) async {
    _hash = _h(pin);
    await _p?.setString('pin_hash', _hash!);
    notifyListeners();
  }

  Future<void> setLocked(String chatId, bool value) async {
    if (value) {
      _locked.add(chatId);
    } else {
      _locked.remove(chatId);
    }
    await _p?.setStringList('locked_chats', _locked.toList());
    notifyListeners();
  }
}

Future<String?> _pinDialog(BuildContext context, String title, {String? hint}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        decoration: InputDecoration(
          hintText: hint ?? '4-8 digit PIN',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// PIN set cheythittillenkil puthiyathu undaakkum. True = PIN ready.
Future<bool> ensurePinSet(BuildContext context) async {
  final lock = LockService.instance;
  if (lock.hasPin) return true;
  final p1 = await _pinDialog(context, 'Create a chat lock PIN');
  if (p1 == null || !context.mounted) return false;
  if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
    snack(context, 'PIN must be 4 to 8 digits.');
    return false;
  }
  final p2 = await _pinDialog(context, 'Confirm PIN');
  if (p2 == null || !context.mounted) return false;
  if (p1 != p2) {
    snack(context, 'PINs did not match.');
    return false;
  }
  await lock.setPin(p1);
  return true;
}

Future<bool> askPin(
  BuildContext context, {
  String title = 'Enter chat lock PIN',
}) async {
  final lock = LockService.instance;
  if (!lock.hasPin) return true;
  final p = await _pinDialog(context, title);
  if (p == null) return false;
  if (lock.verify(p)) return true;
  if (context.mounted) snack(context, 'Wrong PIN.');
  return false;
}

Future<void> changePin(BuildContext context) async {
  final lock = LockService.instance;
  if (lock.hasPin) {
    final ok = await askPin(context, title: 'Enter current PIN');
    if (!ok || !context.mounted) return;
    final p1 = await _pinDialog(context, 'New PIN');
    if (p1 == null || !context.mounted) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(p1)) {
      snack(context, 'PIN must be 4 to 8 digits.');
      return;
    }
    await lock.setPin(p1);
    if (context.mounted) snack(context, 'PIN changed.');
  } else {
    final ok = await ensurePinSet(context);
    if (ok && context.mounted) snack(context, 'PIN created.');
  }
}
