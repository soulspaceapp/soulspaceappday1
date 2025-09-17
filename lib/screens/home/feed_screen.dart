import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final TextEditingController _postController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser!;

  Future<void> _createPost() async {
    if (_postController.text.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection("posts").add({
      "text": _postController.text.trim(),
      "userId": user.uid,
      "timestamp": FieldValue.serverTimestamp(),
      "reactions": {},
    });

    _postController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SoulSpace Feed"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          // Post input
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _postController,
                    decoration: const InputDecoration(
                      hintText: "Share your thoughts...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _createPost,
                  child: const Text("Post"),
                ),
              ],
            ),
          ),

          // Feed stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("posts")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return PostCard(postId: post.id, data: post.data() as Map<String, dynamic>);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Post Card ----------------

class PostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;

  const PostCard({super.key, required this.postId, required this.data});

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final doc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();
    return doc.data() ?? {};
  }

  void _react(String type) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final postRef = FirebaseFirestore.instance.collection("posts").doc(postId);

    FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(postRef);
      final reactions = Map<String, dynamic>.from(snapshot["reactions"] ?? {});

      // remove old reaction by this user
      reactions.removeWhere((key, value) => value == uid);

      // add new reaction
      reactions[type] = uid;

      transaction.update(postRef, {"reactions": reactions});
    });
  }

  void _addReply(BuildContext context) async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Reply"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Write something..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection("posts")
                    .doc(postId)
                    .collection("replies")
                    .add({
                  "text": controller.text.trim(),
                  "userId": FirebaseAuth.instance.currentUser!.uid,
                  "timestamp": FieldValue.serverTimestamp(),
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text("Reply"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = data["text"] ?? "";
    final userId = data["userId"] ?? "";
    final reactions = Map<String, dynamic>.from(data["reactions"] ?? {});

    // count reactions
    final heartCount =
        reactions.entries.where((e) => e.key == "heart").length;
    final careCount = reactions.entries.where((e) => e.key == "care").length;

    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserData(userId),
      builder: (context, snapshot) {
        final author = snapshot.data ?? {};
        final avatar = (author["avatar"] as String?)?.isNotEmpty == true
            ? author["avatar"]
            : "https://i.pravatar.cc/150?img=1";
        final name = (author["name"] as String?)?.isNotEmpty == true
            ? author["name"]
            : "Anonymous";

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(backgroundImage: NetworkImage(avatar)),
                    const SizedBox(width: 8),
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(text),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red),
                      onPressed: () => _react("heart"),
                    ),
                    Text("$heartCount"),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.volunteer_activism,
                          color: Colors.purple),
                      onPressed: () => _react("care"),
                    ),
                    Text("$careCount"),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _addReply(context),
                      child: const Text("Reply"),
                    ),
                  ],
                ),
                ReplySection(postId: postId),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------- Reply Section ----------------

class ReplySection extends StatelessWidget {
  final String postId;

  const ReplySection({super.key, required this.postId});

  Future<Map<String, dynamic>> _getUserData(String userId) async {
    final doc =
        await FirebaseFirestore.instance.collection("users").doc(userId).get();
    return doc.data() ?? {};
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("posts")
          .doc(postId)
          .collection("replies")
          .orderBy("timestamp", descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final replies = snapshot.data!.docs;

        return Column(
          children: replies.map((reply) {
            final data = reply.data() as Map<String, dynamic>;
            final text = data["text"] ?? "";
            final userId = data["userId"] ?? "";

            return FutureBuilder<Map<String, dynamic>>(
              future: _getUserData(userId),
              builder: (context, snapshot) {
                final author = snapshot.data ?? {};
                final avatar =
                    (author["avatar"] as String?)?.isNotEmpty == true
                        ? author["avatar"]
                        : "https://i.pravatar.cc/150?img=1";
                final name = (author["name"] as String?)?.isNotEmpty == true
                    ? author["name"]
                    : "Anonymous";

                return ListTile(
                  leading: CircleAvatar(backgroundImage: NetworkImage(avatar)),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(text),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}
