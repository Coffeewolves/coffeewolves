import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendConnectionsService {
  FriendConnectionsService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _requests(String uid) =>
      _firestore.collection('users').doc(uid).collection('friendRequests');

  Future<void> sendRequest({
    required String senderUid,
    required String senderDisplayName,
    required String recipientUid,
  }) async {
    if (senderUid == recipientUid) {
      throw ArgumentError('No puedes enviarte una solicitud a ti mismo.');
    }

    final recipientProfile = _firestore.collection('users').doc(recipientUid);
    final existingFriendship = _firestore
        .collection('users')
        .doc(senderUid)
        .collection('friends')
        .doc(recipientUid);
    final request = _requests(recipientUid).doc(senderUid);

    await _firestore.runTransaction<void>((transaction) async {
      final recipientSnapshot = await transaction.get(recipientProfile);
      final friendshipSnapshot = await transaction.get(existingFriendship);
      final requestSnapshot = await transaction.get(request);

      if (!recipientSnapshot.exists) {
        throw StateError('No encontramos un usuario con ese ID.');
      }
      if (friendshipSnapshot.exists) {
        throw StateError('Ya son amigos.');
      }
      final previousRequest = requestSnapshot.data();
      if (requestSnapshot.exists && previousRequest?['status'] != 'rejected') {
        throw StateError('Ya existe una solicitud para este usuario.');
      }

      final requestData = {
        'fromDisplayName': senderDisplayName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (requestSnapshot.exists) {
        transaction.update(request, requestData);
      } else {
        transaction.set(request, {
          ...requestData,
          'fromUid': senderUid,
        });
      }
    });
  }

}

class FriendConnectionsPanel extends StatefulWidget {
  const FriendConnectionsPanel({
    super.key,
    required this.user,
    required this.displayName,
    this.service,
  });

  final User user;
  final String displayName;
  final FriendConnectionsService? service;

  @override
  State<FriendConnectionsPanel> createState() => _FriendConnectionsPanelState();
}

class _FriendConnectionsPanelState extends State<FriendConnectionsPanel> {
  static const _gold = Color(0xFFC6A06A);
  static const _muted = Color(0xFFB7AA9D);
  static const _panel = Color(0xFF211D19);
  static const _error = Color(0xFFFF8A80);

  final _recipientUidController = TextEditingController();
  late final FriendConnectionsService _service;
  bool _isWorking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? FriendConnectionsService(FirebaseFirestore.instance);
  }

  @override
  void dispose() {
    _recipientUidController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final recipientUid = _recipientUidController.text.trim();
    if (recipientUid.isEmpty) {
      setState(() => _message = 'Escribe el UID de la persona.');
      return;
    }
    setState(() {
      _isWorking = true;
      _message = null;
    });
    try {
      await _service.sendRequest(
        senderUid: widget.user.uid,
        senderDisplayName: widget.displayName,
        recipientUid: recipientUid,
      );
      if (!mounted) return;
      _recipientUidController.clear();
      setState(() => _message = 'Solicitud enviada.');
    } catch (error, stackTrace) {
      debugPrint('No se pudo enviar la solicitud de amistad: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _message = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _messageFor(Object error) => error is StateError
      ? error.message
      : 'No se pudo completar la acción. Comprueba la conexión e inténtalo '
          'de nuevo.';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'AMIGOS',
          style: TextStyle(
            color: _gold,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _recipientUidController,
          enabled: !_isWorking,
          decoration: const InputDecoration(
            labelText: 'UID de la persona',
            helperText: 'Pídele su UID para enviarle una solicitud.',
            prefixIcon: Icon(Icons.person_add_alt_1),
            filled: true,
            fillColor: _panel,
            helperStyle: TextStyle(color: _muted, fontSize: 10),
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _isWorking ? null : _sendRequest,
          icon: const Icon(Icons.send_outlined),
          label: const Text('ENVIAR SOLICITUD'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 6),
          Text(
            _message!,
            style: TextStyle(
              color: _message == 'Solicitud enviada.'
                  ? const Color(0xFFB8C89A)
                  : _error,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
