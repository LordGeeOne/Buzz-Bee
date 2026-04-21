import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hugeicons/hugeicons.dart';

import '../services/connection_service.dart';
import '../theme/nexaryo_colors.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _hasSearched = false;
  bool _isSearching = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final lowerQuery = query.toLowerCase();

      // Search by name prefix
      final nameQuery = FirebaseFirestore.instance
          .collection('users')
          .where('nameLower', isGreaterThanOrEqualTo: lowerQuery)
          .where('nameLower', isLessThanOrEqualTo: '$lowerQuery\uf8ff')
          .limit(20)
          .get();

      // Search by exact username
      final usernameQuery = FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: lowerQuery)
          .limit(5)
          .get();

      final results = await Future.wait([nameQuery, usernameQuery]);

      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final snapshot in results) {
        for (final doc in snapshot.docs) {
          if (doc.id != _myUid && seen.add(doc.id)) {
            merged.add({'uid': doc.id, ...doc.data()});
          }
        }
      }

      setState(() => _searchResults = merged);
    } catch (_) {
      setState(() => _searchResults = []);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<bool> _isAlreadyConnected() async {
    if (_myUid.isEmpty) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_myUid)
        .get();
    final connId = (doc.data()?['connectionId'] as String?) ?? '';
    return connId.isNotEmpty;
  }

  Future<void> _sendRequest(String toUid) async {
    if (await _isAlreadyConnected()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "You're already connected. Disconnect first to send a new request.",
            style: GoogleFonts.montserrat(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await ConnectionService.sendRequest(toUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request sent!', style: GoogleFonts.montserrat()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e', style: GoogleFonts.montserrat())),
      );
    }
  }

  Future<void> _acceptRequest(String fromUid) async {
    try {
      await ConnectionService.acceptRequest(fromUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected!', style: GoogleFonts.montserrat()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Failed: $e',
            style: GoogleFonts.montserrat(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String fromUid) async {
    await ConnectionService.rejectRequest(fromUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Request rejected', style: GoogleFonts.montserrat()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _showUserPopup(Map<String, dynamic> user, {bool isRequest = false}) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              if (isRequest) ...[
                _buildUserInfo(c, user),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        c,
                        label: 'Accept',
                        color: c.primary,
                        onTap: () {
                          Navigator.pop(ctx);
                          _acceptRequest(user['uid']);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionButton(
                        c,
                        label: 'Reject',
                        color: c.accentWarm,
                        onTap: () {
                          Navigator.pop(ctx);
                          _rejectRequest(user['uid']);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _actionButton(
                  c,
                  label: 'View Details',
                  color: c.textSecondary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDetailsPopup(user);
                  },
                ),
              ] else ...[
                _buildUserInfo(c, user),
                const SizedBox(height: 24),
                _actionButton(
                  c,
                  label: 'Send Request',
                  color: c.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendRequest(user['uid']);
                  },
                ),
                const SizedBox(height: 12),
                _actionButton(
                  c,
                  label: 'View Details',
                  color: c.textSecondary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showDetailsPopup(user);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showDetailsPopup(Map<String, dynamic> user) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(34),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(user, radius: 40),
                const SizedBox(height: 16),
                Text(
                  user['name'] ?? 'User',
                  style: TextStyle(
                    fontFamily: 'Miloner',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                if (user['username'] != null &&
                    (user['username'] as String).isNotEmpty)
                  Text(
                    '@${user['username']}',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      color: c.textDim,
                    ),
                  ),
                if (user['email'] != null &&
                    (user['email'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user['email'],
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: c.textDim,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _actionButton(
                    c,
                    label: 'Close',
                    color: c.textSecondary,
                    onTap: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserInfo(NexaryoColors c, Map<String, dynamic> user) {
    return Column(
      children: [
        _avatar(user, radius: 32),
        const SizedBox(height: 12),
        Text(
          user['name'] ?? 'User',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _avatar(Map<String, dynamic> user, {double radius = 20}) {
    final c = context.colors;
    final photo = user['photoURL'] ?? user['fromPhoto'] ?? '';
    if (photo.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(photo));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.cardBorder,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        color: c.textSecondary,
        size: radius * 0.9,
      ),
    );
  }

  Widget _actionButton(
    NexaryoColors c, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(34),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(34),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    height: 68,
                    width: 68,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(34),
                    ),
                    child: IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowLeft01,
                        color: c.textDim,
                        size: 24,
                      ),
                      iconSize: 24,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'People',
                    style: GoogleFonts.montserrat(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.montserrat(
                        color: c.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        hintStyle: GoogleFonts.montserrat(
                          color: c.textDim,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: c.card,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(34),
                          borderSide: BorderSide(color: c.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(34),
                          borderSide: BorderSide(color: c.primary),
                        ),
                      ),
                      onSubmitted: (_) => _searchUsers(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch01,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _searchUsers,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _hasSearched ? _buildSearchResults(c) : _buildRequests(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(NexaryoColors c) {
    if (_isSearching) {
      return Center(child: CircularProgressIndicator(color: c.primary));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No users found',
          style: GoogleFonts.montserrat(fontSize: 14, color: c.textDim),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _userTile(c, user, isRequest: false);
      },
    );
  }

  Widget _buildRequests(NexaryoColors c) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .collection('requests')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: c.primary));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedUserGroup,
                  color: c.cardBorder,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'No pending requests',
                  style: GoogleFonts.montserrat(fontSize: 14, color: c.textDim),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final user = {
              'uid': docs[index].id,
              'name': data['fromName'] ?? 'User',
              'photoURL': data['fromPhoto'] ?? '',
            };
            return _userTile(c, user, isRequest: true);
          },
        );
      },
    );
  }

  Widget _userTile(
    NexaryoColors c,
    Map<String, dynamic> user, {
    required bool isRequest,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(34),
        child: InkWell(
          onTap: () => _showUserPopup(user, isRequest: isRequest),
          borderRadius: BorderRadius.circular(34),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.cardBorder),
            ),
            child: Row(
              children: [
                _avatar(user),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    user['name'] ?? 'User',
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: c.textDim,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
