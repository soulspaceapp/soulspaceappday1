import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// FeedScreen is a *body widget* (no Scaffold) so HomeScreen controls AppBar.
/// It shows:
///  - post input row at top
///  - posts list (author avatar+name, content)
///  - reactions (one per user) with counters
///  - replies (subcollection) with add/delete and bad comment replacement
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final TextEditingController _postController = TextEditingController();
  final List<String> bannedWords = ['stupid', 'idiot', 'kill', 'hate'];

  Future<Map<String, dynamic>> _getUserDoc(String? uid) async {
    if (uid == null || uid.isEmpty) return {};
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return {};
    return doc.data() ?? {};
  }

  Future<bool> _isBanned(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data();
    return data != null && (data['banned'] == true);
  }

  bool _containsBanned(String text) {
    final lower = text.toLowerCase();
    for (final w in bannedWords) {
      if (lower.contains(w)) return true;
    }
    return false;
  }

  Future<void> _createPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (await _isBanned(user.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are banned from posting.')),
      );
      return;
    }
    final text = _postController.text.trim();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance.collection('posts').add({
      'text': text,
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'reactions': {}, // map userId -> reaction string
    });
    _postController.clear();
  }

  // toggles the current user's reaction (one reaction per user)
  Future<void> _toggleReaction(String postId, String reactionType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(postRef);
      final data = snap.data();
      final Map<String, dynamic> reactions = Map<String, dynamic>.from(data?['reactions'] ?? {});
      final current = reactions[user.uid] as String?;
      if (current == reactionType) {
        reactions.remove(user.uid);
      } else {
        reactions[user.uid] = reactionType;
      }
      tx.update(postRef, {'reactions': reactions});
    });
  }

  /// Add reply to subcollection; applies bad-word filter and increments warnings if needed.
  Future<void> _addReply(String postId, String rawText) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (await _isBanned(user.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are banned from replying.')));
      return;
    }

    String text = rawText.trim();
    bool filtered = false;
    if (_containsBanned(text)) {
      text = '⚔️ A bad comment has been slashed by Soul Guardian';
      filtered = true;
    }

    final repliesRef = FirebaseFirestore.instance.collection('posts').doc(postId).collection('replies');
    await repliesRef.add({
      'text': text,
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'isFiltered': filtered,
    });

    if (filtered) {
      // increment warnings; ban if >=5
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snapshot = await tx.get(userDocRef);
        int warnings = (snapshot.exists && snapshot.data()?['warnings'] != null) ? (snapshot.data()?['warnings'] as int) : 0;
        warnings += 1;
        final banned = warnings >= 5;
        tx.set(userDocRef, {'warnings': warnings, 'banned': banned}, SetOptions(merge: true));
      });
    }
  }

  Future<void> _deletePostIfOwner(String postId, String ownerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != ownerId) return;
    await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
  }

  Future<void> _deleteReplyIfOwner(String postId, String replyId, String ownerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != ownerId) return;
    await FirebaseFirestore.instance.collection('posts').doc(postId).collection('replies').doc(replyId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // post input row (keeps post button visible)
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _postController,
                  decoration: const InputDecoration(
                    hintText: 'Share your thoughts...',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _createPost,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                child: const Text('Post'),
              )
            ],
          ),
        ),

        const Divider(height: 0),

        // posts list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('posts').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Text('No posts yet. Be the first!'));
              }

              final docs = snap.data!.docs;
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final postId = doc.id;
                  final postData = doc.data() as Map<String, dynamic>? ?? {};

                  final content = (postData['text'] as String?) ?? '';
                  final authorId = (postData['userId'] as String?) ?? '';
                  final reactions = Map<String, dynamic>.from(postData['reactions'] ?? {});

                  // compute counts
                  final likeCount = reactions.values.where((v) => v == 'like' || v == 'heart' || v == '❤️').length;
                  final careCount = reactions.values.where((v) => v == 'care' || v == '🤗').length;
                  final supportCount = reactions.values.where((v) => v == 'support' || v == '👍').length;

                  return FutureBuilder<Map<String, dynamic>>(
                    future: _getUserDoc(authorId),
                    builder: (context, userSnap) {
                      final author = userSnap.data ?? {};
                      final name = (author['name'] as String?)?.isNotEmpty == true ? author['name'] as String : 'Anonymous';
                      final avatar = (author['avatar'] as String?)?.isNotEmpty == true ? author['avatar'] as String : 'https://i.pravatar.cc/150?img=1';

                      final currentUid = FirebaseAuth.instance.currentUser?.uid;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // header row: avatar, name, (delete if owner)
                              Row(
                                children: [
                                  CircleAvatar(backgroundImage: NetworkImage(avatar)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  if (authorId.isNotEmpty && currentUid == authorId)
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deletePostIfOwner(postId, authorId),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // content
                              Text(content, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 12),
                              // reactions row
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _toggleReaction(postId, 'like'),
                                    icon: const Text('❤️', style: TextStyle(fontSize: 18)),
                                    label: Text(likeCount.toString()),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => _toggleReaction(postId, 'care'),
                                    icon: const Text('🤗', style: TextStyle(fontSize: 18)),
                                    label: Text(careCount.toString()),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => _toggleReaction(postId, 'support'),
                                    icon: const Text('👍', style: TextStyle(fontSize: 18)),
                                    label: Text(supportCount.toString()),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      // open inline reply composer (scrolls to bottom of post card)
                                      showDialog(
                                        context: context,
                                        builder: (_) {
                                          final replyController = TextEditingController();
                                          return AlertDialog(
                                            title: const Text('Reply'),
                                            content: TextField(
                                              controller: replyController,
                                              decoration: const InputDecoration(hintText: 'Type something positive...'),
                                              maxLines: 3,
                                            ),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                              ElevatedButton(
                                                onPressed: () {
                                                  final txt = replyController.text.trim();
                                                  if (txt.isNotEmpty) {
                                                    _addReply(postId, txt);
                                                  }
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Post Reply'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                    child: const Text('Reply'),
                                  ),
                                ],
                              ),

                              // replies list (subcollection)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance.collection('posts').doc(postId).collection('replies').orderBy('timestamp', descending: false).snapshots(),
                                  builder: (context, repliesSnap) {
                                    if (!repliesSnap.hasData) return const SizedBox.shrink();
                                    final repliesDocs = repliesSnap.data!.docs;
                                    return Column(
                                      children: repliesDocs.map((r) {
                                        final rid = r.id;
                                        final rd = r.data() as Map<String, dynamic>? ?? {};
                                        final rtext = (rd['text'] as String?) ?? '';
                                        final ruid = (rd['userId'] as String?) ?? '';
                                        final isFiltered = (rd['isFiltered'] == true);

                                        return FutureBuilder<Map<String, dynamic>>(
                                          future: _getUserDoc(ruid),
                                          builder: (context, aSnap) {
                                            final a = aSnap.data ?? {};
                                            final rname = (a['name'] as String?)?.isNotEmpty == true ? a['name'] as String : 'Anonymous';
                                            final ravatar = (a['avatar'] as String?)?.isNotEmpty == true ? a['avatar'] as String : 'https://i.pravatar.cc/150?img=1';
                                            final curUid = FirebaseAuth.instance.currentUser?.uid;

                                            return ListTile(
                                              dense: true,
                                              leading: CircleAvatar(backgroundImage: NetworkImage(ravatar), radius: 16),
                                              title: Text(rname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                              subtitle: Text(rtext),
                                              trailing: (curUid != null && curUid == ruid)
                                                  ? IconButton(
                                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                                      onPressed: () => _deleteReplyIfOwner(postId, rid, ruid),
                                                    )
                                                  : null,
                                            );
                                          },
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
