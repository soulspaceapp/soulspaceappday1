import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser!;
  String? name;
  String? email;
  String? avatar;

  final List<String> avatarOptions = [
    "https://i.pravatar.cc/150?img=1",
    "https://i.pravatar.cc/150?img=2",
    "https://i.pravatar.cc/150?img=3",
    "https://i.pravatar.cc/150?img=4",
    "https://i.pravatar.cc/150?img=5",
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    setState(() {
      name = doc["name"];
      email = doc["email"];
      avatar = doc["avatar"] ?? avatarOptions.first;
    });
  }

  Future<void> _updateAvatar(String url) async {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .update({"avatar": url});
    setState(() {
      avatar = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (name == null || email == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 👤 Current Avatar
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(avatar ?? avatarOptions.first),
            ),
            const SizedBox(height: 10),

            Text(
              name!,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              email!,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),

            const SizedBox(height: 20),
            const Text(
              "Choose Your Avatar",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // 🖼️ Avatar options
            Wrap(
              spacing: 10,
              children: avatarOptions.map((url) {
                return GestureDetector(
                  onTap: () => _updateAvatar(url),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage: NetworkImage(url),
                    child: avatar == url
                        ? const Icon(Icons.check_circle,
                            color: Colors.green, size: 30)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
