import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ividuthe 2 vilakal mathram maattiyaal mathi
/// (Supabase dashboard -> Project Settings -> API Keys).
class AppConfig {
  static const String supabaseUrl = 'https://cpjorpdzqjjdvblbzknk.supabase.co';
  static const String supabaseKey =
      'sb_publishable_KVFY9a5X2tr3y6DifX-aLg_DYtaYxH5';

  /// Calls-inu vendi free STUN + free public TURN.
  /// TURN illenkil chila mobile networks-il call connect aavilla.
  static const List<Map<String, dynamic>> iceServers = [
    {
      'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
    },
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
        'turn:openrelay.metered.ca:443?transport=tcp',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];
}

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

SupabaseClient get sb => Supabase.instance.client;
String get myId => sb.auth.currentUser!.id;

class AppInfo {
  static const String appName = 'OruChat';
  static const String version = '2.0.0';
  static const String studioName = 'Oru Design Creative Studio';
  static const String studioSite = 'https://www.orudesign.in';
  static const String upiId = 'ananduaman1-1@oksbi';
}
