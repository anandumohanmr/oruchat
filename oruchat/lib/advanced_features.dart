import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'utils.dart';

const _secure = FlutterSecureStorage();

/// Device-local chat lock. The PIN is stored in Android Keystore/iOS Keychain.
class ChatLock {
  static String _key(String chatId) => 'oru_chat_lock_$chatId';

  static Future<bool> isLocked(String chatId) async =>
      (await _secure.read(key: _key(chatId))) != null;

  static Future<void> setPin(String chatId, String pin) =>
      _secure.write(key: _key(chatId), value: pin);

  static Future<void> remove(String chatId) => _secure.delete(key: _key(chatId));

  static Future<bool> unlock(BuildContext context, String chatId) async {
    final stored = await _secure.read(key: _key(chatId));
    if (stored == null) return true;
    try {
      final auth = LocalAuthentication();
      if (await auth.isDeviceSupported() && await auth.canCheckBiometrics) {
        final ok = await auth.authenticate(
          localizedReason: 'Unlock this OruChat conversation',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (ok) return true;
      }
    } catch (_) {}
    if (!context.mounted) return false;
    final c = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat locked'),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Enter chat PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Unlock')),
        ],
      ),
    );
    return entered != null && entered == stored;
  }

  static Future<void> configure(BuildContext context, String chatId) async {
    final existing = await isLocked(chatId);
    if (existing) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chat lock enabled'),
          content: const Text('Remove the PIN and biometric lock for this chat?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep locked')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove lock')),
          ],
        ),
      );
      if (remove == true) await ChatLock.remove(chatId);
      return;
    }
    final a = TextEditingController();
    final b = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set chat PIN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN (4–8 digits)')),
          TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Confirm PIN')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (a.text.length >= 4 && a.text.length <= 8 && RegExp(r'^\d+$').hasMatch(a.text) && a.text == b.text) {
              Navigator.pop(ctx, a.text);
            } else {
              snack(ctx, 'Enter matching 4–8 digit PINs');
            }
          }, child: const Text('Enable')),
        ],
      ),
    );
    if (pin != null) await ChatLock.setPin(chatId, pin);
  }
}

class MessageExpiry {
  static const choices = <String, Duration?>{
    'Off': null,
    '1 minute': Duration(minutes: 1),
    '1 hour': Duration(hours: 1),
    '24 hours': Duration(hours: 24),
    '1 month': Duration(days: 30),
  };

  static Future<int?> choose(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Disappearing messages', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final name in choices.keys)
          ListTile(title: Text(name), onTap: () => Navigator.pop(ctx, name)),
      ])),
    );
    if (selected == null) return null;
    final duration = choices[selected];
    return duration?.inSeconds ?? 0;
  }
}

const storyFilterNames = <String>[
  'Original','Vivid','Warm','Cool','Mono','Noir','Sepia','Vintage',
  'Soft','Fade','Bright','Matte','Rose','Golden','Ocean','Forest',
  'Lavender','Amber','Ice','Dramatic','Pastel','Cinematic','B&W Soft','Pop'
];

/// Applies the selected filter to the actual image bytes before uploading.
Uint8List applyStoryFilter(Uint8List bytes, int filter) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw Exception('Unsupported image format');
  for (final p in decoded) {
    var r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final gray = 0.299 * r + 0.587 * g + 0.114 * b;
    switch (filter) {
      case 1: r *= 1.18; g *= 1.08; b *= 0.98; break;
      case 2: r = r * 1.08 + 8; g = g * 1.02; b *= 0.88; break;
      case 3: r *= 0.90; g *= 1.02; b = b * 1.12 + 5; break;
      case 4: r = g = b = gray; break;
      case 5: r = g = b = gray * (gray < 128 ? 0.72 : 1.12); break;
      case 6: r = gray * 1.08 + 22; g = gray * 0.94 + 8; b = gray * 0.78; break;
      case 7: r = r * 0.92 + 18; g = g * 0.88 + 12; b = b * 0.78 + 5; break;
      case 8: r = r * 0.92 + 12; g = g * 0.92 + 12; b = b * 0.92 + 12; break;
      case 9: r = r * 0.82 + 35; g = g * 0.82 + 35; b = b * 0.82 + 35; break;
      case 10: r = r * 1.15 + 12; g = g * 1.15 + 12; b = b * 1.15 + 12; break;
      case 11: r = r * 0.88 + 22; g = g * 0.88 + 22; b = b * 0.88 + 22; break;
      case 12: r = r * 1.10 + 8; g *= 0.90; b *= 1.02; break;
      case 13: r = r * 1.12 + 10; g = g * 1.04 + 4; b *= 0.82; break;
      case 14: r *= 0.82; g = g * 1.02 + 4; b = b * 1.15 + 8; break;
      case 15: r *= 0.86; g = g * 1.08 + 5; b *= 0.88; break;
      case 16: r = r * 1.04 + 8; g *= 0.94; b = b * 1.10 + 8; break;
      case 17: r = r * 1.12 + 10; g = g * 0.94 + 4; b *= 0.78; break;
      case 18: r *= 0.90; g = g * 1.06 + 8; b = b * 1.18 + 12; break;
      case 19: r = r * 1.28 - 12; g = g * 1.16 - 8; b = b * 1.10 - 5; break;
      case 20: r = r * 1.08 + 18; g = g * 1.06 + 18; b = b * 1.08 + 18; break;
      case 21: r = r * 1.08 + 4; g = g * 0.98 + 2; b *= 0.92; break;
      case 22: r = g = b = gray * 0.88 + 20; break;
      case 23: r = r * 1.24 + 10; g *= 0.92; b = b * 1.18 + 8; break;
    }
    p.r = r.clamp(0, 255); p.g = g.clamp(0, 255); p.b = b.clamp(0, 255);
  }
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
}

class StoryFilterPage extends StatefulWidget {
  const StoryFilterPage({super.key, required this.bytes});
  final Uint8List bytes;
  @override State<StoryFilterPage> createState() => _StoryFilterPageState();
}
class _StoryFilterPageState extends State<StoryFilterPage> {
  int selected = 0;
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Choose a filter'), actions: [TextButton(onPressed: () => Navigator.pop(context, applyStoryFilter(widget.bytes, selected)), child: const Text('Use filter'))]),
    body: Column(children: [Expanded(child: Center(child: Image.memory(applyStoryFilter(widget.bytes, selected), fit: BoxFit.contain))), SizedBox(height: 112, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: storyFilterNames.length, itemBuilder: (ctx, i) => GestureDetector(onTap: () => setState(() => selected = i), child: Container(width: 88, margin: const EdgeInsets.all(6), padding: const EdgeInsets.all(6), decoration: BoxDecoration(border: Border.all(color: selected == i ? Colors.white : Colors.white24, width: selected == i ? 2 : 1), borderRadius: BorderRadius.circular(10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(storyFilterNames[i], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11)), const SizedBox(height: 5), Icon(i == 0 ? Icons.image : Icons.auto_awesome, color: Colors.white70)])))))]),
  );
}

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});
  @override State<GroupsPage> createState() => _GroupsPageState();
}
class _GroupsPageState extends State<GroupsPage> {
  bool busy = false;
  Future<void> createGroup() async {
    final name = TextEditingController();
    final usernames = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Create group'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')), TextField(controller: usernames, decoration: const InputDecoration(labelText: 'Usernames (comma separated)'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))]));
    if (ok != true || name.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final group = await sb.from('chat_groups').insert({'name': name.text.trim(), 'created_by': myId}).select().single();
      await sb.from('chat_group_members').insert({'group_id': group['id'], 'user_id': myId, 'role': 'admin'});
      for (final u in usernames.text.split(',').map((e) => e.trim().replaceFirst('@', '').toLowerCase()).where((e) => e.isNotEmpty)) {
        final p = await sb.from('profiles').select('id').eq('username', u).maybeSingle();
        if (p != null && p['id'] != myId) {
          await sb.from('chat_group_members').upsert({'group_id': group['id'], 'user_id': p['id'], 'role': 'member'}, onConflict: 'group_id,user_id');
        }
      }
      if (mounted) snack(context, 'Group created');
    } catch (e) { if (mounted) snack(context, 'Could not create group: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Groups'), actions: [IconButton(onPressed: busy ? null : createGroup, icon: const Icon(Icons.group_add))]), body: StreamBuilder<List<Map<String,dynamic>>>(stream: sb.from('chat_group_members').stream(primaryKey: ['id']).eq('user_id', myId), builder: (ctx, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final ids = snap.data!.map((e) => e['group_id']).toSet().toList();
    if (ids.isEmpty) return const Center(child: Text('No groups yet. Create a group to get started.'));
    return FutureBuilder<List<Map<String,dynamic>>>(future: sb.from('chat_groups').select().inFilter('id', ids).order('created_at', ascending: false), builder: (ctx, gs) {
      if (!gs.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(children: [for (final g in gs.data!) ListTile(leading: const CircleAvatar(child: Icon(Icons.groups)), title: Text(g['name'] ?? 'Group'), subtitle: const Text('Group conversation'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatPage(group: g))))]);
    });
  }));
}

class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({super.key, required this.group});
  final Map<String,dynamic> group;
  @override State<GroupMembersPage> createState() => _GroupMembersPageState();
}
class _GroupMembersPageState extends State<GroupMembersPage> {
  Future<void> addMember() async {
    final c = TextEditingController();
    final username = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add member'), content: TextField(controller: c, decoration: const InputDecoration(prefixText: '@', labelText: 'Username')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim().replaceFirst('@','').toLowerCase()), child: const Text('Add'))]));
    if (username == null || username.isEmpty) return;
    try {
      final profile = await sb.from('profiles').select('id').eq('username', username).maybeSingle();
      if (profile == null) { if(mounted) snack(context,'User not found'); return; }
      await sb.from('chat_group_members').insert({'group_id':widget.group['id'],'user_id':profile['id'],'role':'member'});
      if(mounted) snack(context,'Member added');
    } catch(e) { if(mounted) snack(context,'Could not add member: $e'); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Group members'),actions:[IconButton(onPressed:addMember,icon:const Icon(Icons.person_add_alt_1))]),body:StreamBuilder<List<Map<String,dynamic>>>(stream:sb.from('chat_group_members').stream(primaryKey:['id']).eq('group_id',widget.group['id']),builder:(ctx,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(children:[for(final m in s.data!) FutureBuilder<Map<String,dynamic>>(future:ProfileCache.get(m['user_id']),initialData:ProfileCache.peek(m['user_id']),builder:(ctx,p){final profile=p.data??{'display_name':'Loading…'};return ListTile(leading:Avatar(name:profile['display_name']??'?',url:profile['avatar_url']),title:Text(profile['display_name']??''),subtitle:Text(m['role']??'member'),trailing:m['user_id']==myId?const Text('You'):null);})]);}));
}

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key, required this.group});
  final Map<String,dynamic> group;
  @override State<GroupChatPage> createState() => _GroupChatPageState();
}
class _GroupChatPageState extends State<GroupChatPage> {
  final input = TextEditingController();
  late final stream = sb.from('chat_group_messages').stream(primaryKey: ['id']).eq('group_id', widget.group['id']).order('created_at');
  Future<void> send() async { final t=input.text.trim(); if(t.isEmpty)return; input.clear(); try { await sb.from('chat_group_messages').insert({'group_id':widget.group['id'],'sender_id':myId,'body':t,'kind':'text'}); } catch(e) { if(mounted) snack(context,'Message failed: $e'); } }
  Future<void> sendFile() async { final picked=await FilePicker.platform.pickFiles(withData:true); if(picked==null||picked.files.single.bytes==null)return; final f=picked.files.single; try { final key='$myId/${DateTime.now().microsecondsSinceEpoch}_${f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'),'_')}'; await sb.storage.from('media').uploadBinary(key,f.bytes!,fileOptions:const FileOptions(contentType:'application/octet-stream')); await sb.from('chat_group_messages').insert({'group_id':widget.group['id'],'sender_id':myId,'body':f.name,'media_url':sb.storage.from('media').getPublicUrl(key),'kind':'file'}); } catch(e){if(mounted)snack(context,'Attachment failed: $e');} }
  @override void dispose(){input.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.group['name']??'Group'),actions:[IconButton(tooltip:'Members',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>GroupMembersPage(group:widget.group))),icon:const Icon(Icons.people_outline))]),body:Column(children:[Expanded(child:StreamBuilder<List<Map<String,dynamic>>>(stream:stream,builder:(ctx,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(12),children:[for(final m in s.data!) Align(alignment:m['sender_id']==myId?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.symmetric(vertical:4),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:m['sender_id']==myId?purple:Colors.white,borderRadius:BorderRadius.circular(14)),child:m['kind']=='file' ? InkWell(onTap:() async { final u=Uri.tryParse(m['media_url']??''); if(u!=null) await launchUrl(u,mode:LaunchMode.externalApplication); }, child:Text('📎 ${m['body']??'Attachment'}',style:TextStyle(color:m['sender_id']==myId?Colors.white:ink))) : Text(m['body']??'',style:TextStyle(color:m['sender_id']==myId?Colors.white:ink))))]);})),SafeArea(child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[IconButton(onPressed:sendFile,icon:const Icon(Icons.attach_file,color:purple)),Expanded(child:TextField(controller:input,decoration:const InputDecoration(hintText:'Message group'))),IconButton(onPressed:send,icon:const Icon(Icons.send,color:purple))])))]));
}
