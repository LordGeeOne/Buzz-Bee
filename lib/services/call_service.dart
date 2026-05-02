import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import '../utils/message_preview.dart';
import 'connection_service.dart';

/// 1:1 voice call signaling + WebRTC orchestration.
///
/// Free / serverless stack:
///   - Signaling: Firestore at `connections/{connId}/calls/{callId}`
///   - STUN: Google's free public servers
///   - No TURN (call may fail behind symmetric NAT — surfaced as `failed`)
///   - Audio-only (`getUserMedia({audio:true,video:false})`)
///
/// Lifecycle states (mirrors the `state` field on the Firestore call doc):
///   - ringing   : caller has written the offer; waiting for callee
///   - accepted  : callee has set the answer; ICE negotiating
///   - connected : RTCPeerConnection has reached `connected`
///   - declined  : callee declined
///   - missed    : callee didn't answer in time
///   - ended     : either side hung up after connect
///   - failed    : ICE never reached connected (likely needs TURN)
class CallSession {
  CallSession({
    required this.callId,
    required this.connectionId,
    required this.peerUid,
    required this.isCaller,
    required this.startedAt,
  });

  final String callId;
  final String connectionId;
  final String peerUid;
  final bool isCaller;
  final DateTime startedAt;

  String state = 'ringing';
  bool muted = false;
  bool speakerOn = false;
  String? peerName;
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const _uuid = Uuid();
  static const _stunServers = <String>[
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
    'stun:stun3.l.google.com:19302',
    'stun:stun4.l.google.com:19302',
  ];

  final _stateController = StreamController<CallSession?>.broadcast();
  Stream<CallSession?> get sessionStream => _stateController.stream;
  CallSession? get current => _current;
  DateTime? get connectedAt => _connectedAt;

  CallSession? _current;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  DateTime? _connectedAt;
  final Set<String> _loggedCallIds = <String>{};

  final List<StreamSubscription<dynamic>> _subs = [];

  bool get inCall => _current != null;

  // ── Public API ──

  /// Caller side: create the call doc + offer, then wait for an answer.
  /// Returns the new callId.
  Future<String> startCall({
    required String connectionId,
    required String calleeUid,
    String? calleeName,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) throw StateError('Not signed in');
    if (_current != null) throw StateError('Already in a call');

    final callId = _uuid.v4();
    final session = CallSession(
      callId: callId,
      connectionId: connectionId,
      peerUid: calleeUid,
      isCaller: true,
      startedAt: DateTime.now(),
    )..peerName = calleeName;
    _current = session;
    _emit();

    await _initPeer(session);

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(offer);

    final callRef = _callRef(connectionId, callId);
    await callRef.set({
      'callId': callId,
      'callerUid': myUid,
      'calleeUid': calleeUid,
      'state': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
    });

    _wireCallerListeners(session, callRef);
    return callId;
  }

  /// Callee side: load the offer from Firestore, build local peer, answer.
  Future<void> answerCall({
    required String callId,
    required String connectionId,
    String? callerName,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) throw StateError('Not signed in');
    if (_current != null && _current!.callId == callId) {
      // Already attached.
      return;
    }
    if (_current != null) {
      // Busy — auto-decline.
      await _writeState(
        connectionId,
        callId,
        'declined',
        extra: {'endReason': 'busy'},
      );
      return;
    }

    final callRef = _callRef(connectionId, callId);
    final snap = await callRef.get();
    final data = snap.data();
    if (data == null) throw StateError('Call not found');
    final callerUid = data['callerUid'] as String?;
    if (callerUid == null) throw StateError('Malformed call doc');

    final session = CallSession(
      callId: callId,
      connectionId: connectionId,
      peerUid: callerUid,
      isCaller: false,
      startedAt: DateTime.now(),
    )..peerName = callerName;
    _current = session;
    _emit();

    await _initPeer(session);

    final offerMap = data['offer'] as Map<String, dynamic>?;
    if (offerMap == null) throw StateError('Missing offer');
    await _pc!.setRemoteDescription(
      RTCSessionDescription(
        offerMap['sdp'] as String?,
        offerMap['type'] as String?,
      ),
    );

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(answer);

    await callRef.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'state': 'accepted',
      'answeredAt': FieldValue.serverTimestamp(),
    });
    session.state = 'accepted';
    _emit();

    _wireCalleeListeners(session, callRef);
  }

  /// Decline an incoming call without ever attaching media.
  Future<void> declineCall({
    required String callId,
    required String connectionId,
  }) async {
    await _writeState(connectionId, callId, 'declined');
  }

  /// Hang up the active call.
  Future<void> endCall({String? endReason}) async {
    final session = _current;
    if (session == null) return;
    final newState = (session.state == 'ringing' || session.state == 'accepted')
        ? (session.isCaller ? 'ended' : 'ended')
        : 'ended';
    try {
      await _writeState(
        session.connectionId,
        session.callId,
        newState,
        extra: {
          if (endReason != null) 'endReason': endReason,
          'endedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (_) {}
    await _teardown();
  }

  Future<void> setMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
    final s = _current;
    if (s != null) {
      s.muted = muted;
      _emit();
    }
  }

  Future<void> setSpeakerOn(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
    final s = _current;
    if (s != null) {
      s.speakerOn = on;
      _emit();
    }
  }

  // ── Internals ──

  DocumentReference<Map<String, dynamic>> _callRef(
    String connectionId,
    String callId,
  ) {
    return FirebaseFirestore.instance
        .collection('connections')
        .doc(connectionId)
        .collection('calls')
        .doc(callId);
  }

  Future<void> _initPeer(CallSession session) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    final config = <String, dynamic>{
      'iceServers': [
        {'urls': _stunServers},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);

    // Add local audio tracks.
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
    };

    _pc!.onIceCandidate = (RTCIceCandidate cand) async {
      if (cand.candidate == null) return;
      final col = session.isCaller ? 'callerCandidates' : 'calleeCandidates';
      try {
        await _callRef(
          session.connectionId,
          session.callId,
        ).collection(col).add({
          'candidate': cand.candidate,
          'sdpMid': cand.sdpMid,
          'sdpMLineIndex': cand.sdpMLineIndex,
        });
      } catch (e) {
        debugPrint('CallService: ICE candidate write failed: $e');
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      final s = _current;
      if (s == null) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          s.state = 'connected';
          _connectedAt ??= DateTime.now();
          _emit();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          s.state = 'failed';
          _emit();
          unawaited(endCall(endReason: 'ice_failed'));
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (s.state != 'ended') {
            unawaited(endCall());
          }
          break;
        default:
          break;
      }
    };
  }

  void _wireCallerListeners(
    CallSession session,
    DocumentReference<Map<String, dynamic>> callRef,
  ) {
    _subs.add(
      callRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data == null) {
          await _teardown();
          return;
        }
        final state = data['state'] as String?;
        if (state == 'declined' ||
            state == 'missed' ||
            state == 'ended' ||
            state == 'failed') {
          if (_current?.callId == session.callId) {
            session.state = state!;
            _emit();
            await _teardown();
          }
          return;
        }
        // Apply remote answer when it arrives.
        final answer = data['answer'] as Map<String, dynamic>?;
        if (answer != null && _pc != null) {
          final remoteDesc = await _pc!.getRemoteDescription();
          if (remoteDesc == null) {
            await _pc!.setRemoteDescription(
              RTCSessionDescription(
                answer['sdp'] as String?,
                answer['type'] as String?,
              ),
            );
            if (state == 'accepted') {
              session.state = 'accepted';
              _emit();
            }
          }
        }
      }),
    );

    // Listen to callee ICE candidates.
    _subs.add(
      callRef.collection('calleeCandidates').snapshots().listen((qs) {
        for (final change in qs.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d == null) continue;
            _pc?.addCandidate(
              RTCIceCandidate(
                d['candidate'] as String?,
                d['sdpMid'] as String?,
                (d['sdpMLineIndex'] as num?)?.toInt(),
              ),
            );
          }
        }
      }),
    );
  }

  void _wireCalleeListeners(
    CallSession session,
    DocumentReference<Map<String, dynamic>> callRef,
  ) {
    _subs.add(
      callRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data == null) {
          await _teardown();
          return;
        }
        final state = data['state'] as String?;
        if (state == 'ended' || state == 'failed' || state == 'missed') {
          if (_current?.callId == session.callId) {
            session.state = state!;
            _emit();
            await _teardown();
          }
        }
      }),
    );

    _subs.add(
      callRef.collection('callerCandidates').snapshots().listen((qs) {
        for (final change in qs.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d == null) continue;
            _pc?.addCandidate(
              RTCIceCandidate(
                d['candidate'] as String?,
                d['sdpMid'] as String?,
                (d['sdpMLineIndex'] as num?)?.toInt(),
              ),
            );
          }
        }
      }),
    );
  }

  Future<void> _writeState(
    String connectionId,
    String callId,
    String state, {
    Map<String, dynamic>? extra,
  }) async {
    final payload = <String, dynamic>{'state': state};
    if (extra != null) payload.addAll(extra);
    try {
      await _callRef(
        connectionId,
        callId,
      ).set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('CallService: state update failed: $e');
    }
  }

  Future<void> _teardown() async {
    final session = _current;
    if (session != null) {
      // Caller writes a single chat-log message describing the outcome,
      // so both peers see it in their chat timeline.
      await _logCallToChat(session);
    }
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      final tracks = _localStream?.getTracks() ?? const [];
      for (final t in tracks) {
        await t.stop();
      }
    } catch (e) {
      debugPrint('CallService: stop tracks failed: $e');
    }
    try {
      await _localStream?.dispose();
    } catch (e) {
      debugPrint('CallService: local stream dispose failed: $e');
    }
    _localStream = null;
    try {
      await _remoteStream?.dispose();
    } catch (e) {
      debugPrint('CallService: remote stream dispose failed: $e');
    }
    _remoteStream = null;
    try {
      await _pc?.close();
    } catch (e) {
      debugPrint('CallService: peer connection close failed: $e');
    }
    _pc = null;
    _current = null;
    _connectedAt = null;
    _emit();
  }

  Future<void> _logCallToChat(CallSession session) async {
    if (!session.isCaller) return;
    if (_loggedCallIds.contains(session.callId)) return;
    _loggedCallIds.add(session.callId);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final connectedAt = _connectedAt;
    final durationMs = connectedAt == null
        ? 0
        : DateTime.now().difference(connectedAt).inMilliseconds;
    final outcome = _resolveOutcome(session.state, durationMs);
    try {
      final connRef = FirebaseFirestore.instance
          .collection('connections')
          .doc(session.connectionId);
      final batch = FirebaseFirestore.instance.batch();
      batch.set(connRef.collection('messages').doc(), {
        'fromUid': myUid,
        'type': 'call',
        'callId': session.callId,
        'peerUid': session.peerUid,
        'callOutcome': outcome,
        'durationMs': durationMs,
        'timestamp': FieldValue.serverTimestamp(),
      });
      batch.update(connRef, {
        'lastActivity': FieldValue.serverTimestamp(),
        'lastMessage': MessagePreview.buildLastMessage(
          type: 'call',
          fromUid: myUid,
          callOutcome: outcome,
        ),
      });
      await batch.commit();
    } catch (_) {}
  }

  String _resolveOutcome(String state, int durationMs) {
    switch (state) {
      case 'declined':
        return 'declined';
      case 'missed':
        return 'missed';
      case 'failed':
        return 'failed';
      case 'connected':
      case 'ended':
        return durationMs > 0 ? 'completed' : 'missed';
      default:
        return 'missed';
    }
  }

  void _emit() {
    _stateController.add(_current);
  }

  /// Helper: deterministic connection id (mirrors ConnectionService).
  static String connectionIdFor(String a, String b) =>
      ConnectionService.connectionIdFor(a, b);
}
